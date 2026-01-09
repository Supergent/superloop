/**
 * Cerebras Transformer - Removes reasoning parameter
 */

'use strict';

module.exports.transformRequest = async function(req) {
  const anthropic = req.body;

  // Remove unsupported parameters
  delete anthropic.reasoning;
  delete anthropic.thinking;

  const model = anthropic.model || 'zai-glm-4.7';
  const openaiMessages = transformMessages(anthropic.messages, anthropic.system);

  const openaiReq = {
    model: model,
    messages: openaiMessages,
    max_tokens: anthropic.max_tokens || 4096,
    temperature: anthropic.temperature || 0.7,
    top_p: anthropic.top_p,
    stream: anthropic.stream !== false,
  };

  if (anthropic.tools && anthropic.tools.length > 0) {
    openaiReq.tools = transformTools(anthropic.tools);
  }

  if (anthropic.tool_choice) {
    openaiReq.tool_choice = transformToolChoice(anthropic.tool_choice);
  }

  if (anthropic.stop_sequences && anthropic.stop_sequences.length > 0) {
    openaiReq.stop = anthropic.stop_sequences;
  }

  // Aggressively remove any reasoning/thinking that might have been added
  delete openaiReq.reasoning;
  delete openaiReq.thinking;

  console.error('[CEREBRAS] Request keys:', Object.keys(openaiReq));

  return {
    ...req,
    body: openaiReq,
    headers: {
      ...req.headers,
      'Content-Type': 'application/json'
    }
  };
};

module.exports.transformResponse = async function(resp) {
  const openai = resp.body;

  if (!openai || typeof openai !== 'object') {
    return resp;
  }

  if (openai.error) {
    return {
      ...resp,
      body: {
        type: 'error',
        error: {
          type: 'api_error',
          message: openai.error.message || 'Unknown error'
        }
      }
    };
  }

  const choice = openai.choices && openai.choices[0];
  if (!choice) {
    return resp;
  }

  const message = choice.message;
  const content = transformResponseContent(message.content);

  const anthropicResp = {
    type: 'message',
    role: 'assistant',
    content: content,
    stop_reason: mapStopReason(choice.finish_reason || 'stop'),
    usage: {
      input_tokens: openai.usage?.prompt_tokens || 0,
      output_tokens: openai.usage?.completion_tokens || 0
    }
  };

  return {
    ...resp,
    body: anthropicResp,
    headers: {
      ...resp.headers,
      'Content-Type': 'application/json'
    }
  };
};

module.exports.transformStreamChunk = async function(chunk) {
  try {
    const data = JSON.parse(chunk);

    if (data.choices && data.choices[0]?.delta?.content) {
      return {
        type: 'content_block_delta',
        index: 0,
        delta: {
          type: 'text',
          text: data.choices[0].delta.content
        }
      };
    }

    if (data.choices && data.choices[0]?.finish_reason) {
      return {
        type: 'message_stop',
        stop_reason: mapStopReason(data.choices[0].finish_reason)
      };
    }

    return null;
  } catch (error) {
    return null;
  }
};

function transformMessages(messages, systemPrompt) {
  const openaiMessages = [];

  if (systemPrompt) {
    openaiMessages.push({
      role: 'system',
      content: systemPrompt
    });
  }

  if (Array.isArray(messages)) {
    for (const msg of messages) {
      const openaiMsg = {
        role: msg.role,
        content: null
      };

      if (typeof msg.content === 'string') {
        openaiMsg.content = msg.content;
      } else if (Array.isArray(msg.content)) {
        openaiMsg.content = flattenContentBlocks(msg.content);
      }

      if (openaiMsg.content !== null) {
        openaiMessages.push(openaiMsg);
      }
    }
  }

  return openaiMessages;
}

function flattenContentBlocks(blocks) {
  const textBlocks = blocks.filter(block => block.type === 'text');
  if (textBlocks.length === 0) return '';
  return textBlocks.map(block => block.text).join('\n\n');
}

function transformTools(tools) {
  if (!Array.isArray(tools)) return [];
  return tools.map(tool => ({
    type: 'function',
    function: {
      name: tool.name,
      description: tool.description,
      parameters: tool.input_schema
    }
  }));
}

function transformToolChoice(toolChoice) {
  if (!toolChoice) return 'auto';
  if (toolChoice.type === 'any' || toolChoice.type === 'auto') return 'auto';
  if (toolChoice.type === 'tool' && toolChoice.name) {
    return {
      type: 'function',
      function: { name: toolChoice.name }
    };
  }
  return 'auto';
}

function transformResponseContent(content) {
  if (!content) return [];
  return [{
    type: 'text',
    text: content
  }];
}

function mapStopReason(finishReason) {
  const mapping = {
    'stop': 'end_turn',
    'length': 'max_tokens',
    'content_filter': 'end_turn',
    'tool_calls': 'tool_use'
  };
  return mapping[finishReason] || 'end_turn';
}
