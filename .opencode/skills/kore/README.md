# KorE Skill for opencode

This skill helps AI agents write correct KorE code by providing syntax reference,
translation patterns, and compile-error avoidance rules.

## Installation

Copy to your opencode config:

```bash
# Per-project
cp -r .opencode/skills/kore/ /path/to/your/project/.opencode/skills/kore/

# Global (all projects)
cp -r .opencode/skills/kore/ ~/.config/opencode/skills/kore/
```

The skill activates automatically when working with `.kore` files or `kore.exs` projects.
