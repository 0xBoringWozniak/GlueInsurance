# Glue Protocol Skill for Claude Code

Build smart contracts and dApps on Glue Protocol with AI assistance.

## Install

### Claude Code (Plugin Marketplace)
\`\`\`
/plugin marketplace add glue-finance/glue-protocol-skill
\`\`\`

### Claude Code (Manual)
\`\`\`bash
git clone https://github.com/glue-finance/glue-protocol-skill.git
cp -r glue-protocol-skill/skills/glue-protocol-dev ~/.claude/skills/
\`\`\`

### OpenSkills (Works with Cursor, Codex, Windsurf, etc.)
\`\`\`bash
npx openskills install glue-finance/glue-protocol-skill
\`\`\`

## What It Does
- Guides building Solidity contracts with Glue Protocol
- Security validation, tokenomics math, deployment guides
- Full workflow: idea → contract → tests → deploy → interface