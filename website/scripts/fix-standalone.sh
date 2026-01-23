#!/usr/bin/env bash
# fixes the standalone directory structure for opennext
# next.js puts it in .next/standalone/website/ due to monorepo detection
# opennext expects it in .next/standalone/

STANDALONE=".next/standalone"

if [ -d "$STANDALONE/website" ]; then
  cp -r "$STANDALONE/website/.next" "$STANDALONE/.next"
  cp -r "$STANDALONE/website/node_modules" "$STANDALONE/node_modules"
  cp "$STANDALONE/website/package.json" "$STANDALONE/package.json"
  cp "$STANDALONE/website/server.js" "$STANDALONE/server.js"
fi
