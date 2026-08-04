#!/usr/bin/env bash
set -euo pipefail

echo "=== KorE Installer ==="

# Check prerequisites
if ! command -v elixir &> /dev/null; then
  echo "Error: Elixir is not installed."
  echo "Install it from https://elixir-lang.org/install.html"
  echo "Required: Elixir >= 1.15, Erlang/OTP >= 25"
  exit 1
fi

if ! command -v mix &> /dev/null; then
  echo "Error: mix is not available (comes with Elixir)."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Fetching dependencies..."
mix deps.get --quiet 2>/dev/null || mix deps.get

echo "Compiling KorE compiler..."
mix compile --quiet 2>/dev/null || mix compile

echo "Building escript..."
mix escript.build

if [ -f "$SCRIPT_DIR/kore" ]; then
  echo ""
  echo "Success! KorE compiler built at: $SCRIPT_DIR/kore"
  echo ""
  echo "Usage:"
  echo "  $SCRIPT_DIR/kore new myapp    # scaffold a project"
  echo "  $SCRIPT_DIR/kore build        # compile .kore -> BEAM"
  echo "  $SCRIPT_DIR/kore run          # build + run Main.main()"
  echo "  $SCRIPT_DIR/kore check        # fast semantic validation"
  echo ""
  echo "To add to PATH:"
  echo "  export PATH=\"$SCRIPT_DIR:\$PATH\""
else
  echo "Error: escript build failed."
  exit 1
fi
