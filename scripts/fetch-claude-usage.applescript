-- fetch-claude-usage.applescript
-- Fetches Claude usage data via Safari (bypasses Cloudflare)

on run argv
    set orgId to item 1 of argv
    set usageUrl to "https://claude.ai/api/organizations/" & orgId & "/usage"

    tell application "Safari"
        -- Open URL in a new tab
        tell window 1
            set newTab to make new tab with properties {URL:usageUrl}
            set currentTab to newTab
        end tell

        -- Wait for page to load (max 10 seconds)
        set maxWait to 10
        set waited to 0
        repeat while waited < maxWait
            delay 0.5
            set waited to waited + 0.5
            tell currentTab
                if (do JavaScript "document.readyState") is "complete" then exit repeat
            end tell
        end repeat

        -- Get the page content (should be JSON)
        tell currentTab
            set pageContent to do JavaScript "document.body.innerText"
        end tell

        -- Close the tab
        tell currentTab to close
    end tell

    return pageContent
end run
