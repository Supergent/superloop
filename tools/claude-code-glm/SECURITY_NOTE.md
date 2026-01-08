# Security Notice

## API Keys in Documentation

⚠️ **IMPORTANT**: The example API keys shown in this documentation are **placeholders only**.

### Before Using This Setup

1. **Get Your Own API Keys:**
   - **Cerebras**: Register at https://cloud.cerebras.ai/
   - **Z.ai**: Register at https://z.ai/model-api

2. **Never Commit Real API Keys:**
   - All examples use placeholder keys like `csk-your-cerebras-api-key-here`
   - Replace these with your actual keys **only in your local VM**
   - Never commit real keys to version control

3. **Key Storage:**
   - Store real keys in VM's `~/.bashrc` (not tracked by git)
   - Use environment variables, not hardcoded values
   - VM filesystem is isolated from git repository

### API Key Rotation

If you've exposed API keys (in screenshots, logs, or commits):

**Cerebras:**
1. Visit https://cloud.cerebras.ai/
2. Navigate to API Keys section
3. Revoke compromised key
4. Generate new key
5. Update in VM: `~/.bashrc`

**Z.ai:**
1. Visit https://z.ai/manage-apikey/apikey-list
2. Delete old key
3. Create new key
4. Update in VM: `~/.bashrc`

### Safe Practices

✅ **DO:**
- Store keys in environment variables
- Use `.bashrc` or similar for persistence
- Keep keys local to the VM
- Rotate keys periodically
- Add `.env` files to `.gitignore`

❌ **DON'T:**
- Commit keys to git
- Share keys in screenshots
- Hardcode keys in scripts
- Share VM snapshots with keys
- Post keys in issues/forums

### This Repository

All API keys in this repository's documentation are **placeholders for demonstration purposes only**. They will not work and should be replaced with your own keys.

---

**Status**: Documentation sanitized and safe for public sharing ✅
