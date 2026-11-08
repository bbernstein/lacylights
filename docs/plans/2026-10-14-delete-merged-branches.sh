#!/bin/sh
# Deletes local branches whose PRs were squash-merged (verified: local tip == merged PR head).
cd ~/src/lacylights
git -C lacylights-go branch -D docs/eos-ascii-format feature/authentication-system feature/bulk-preview-channel-updates feature/copy-fixtures-to-looks feature/eos-ascii-import-export feature/eos-export-loader feature/fixture-data-pubsub feature/mcp-auth feature/undo-redo-cue-cuelist-phase1 feature/undo-redo-phases-5-6-soft-delete fix/auth-priority-jwt-over-device fix/cascade-delete-fixture-values fix/cors-device-fingerprint fix/hurry-button-instant-fade fix/refid-migration-existing-db fix/stop-previous-cuelist-on-start fix/user-group-members-role-migration 
git -C lacylights-fe branch -D docs/eos-ascii-format feature/authentication-system feature/bulk-preview-channel-updates feature/copy-fixtures-to-looks feature/dashboard-effects-card feature/eos-ascii-import-export feature/fixture-data-pubsub feature/history-drawer-improvements feature/mcp-auth feature/multi-tenant-groups feature/scene-to-look-cleanup feature/streamdeck-phase5-frontend feature/streamdeck-plus-design-alignment feature/undo-redo-history fix/add-generate-static-params-to-groups fix/effects-button-aria-labels fix/indigo-primary-blue-display 
git -C lacylights-mcp branch -D deps/combined-updates deps/consolidated-dependabot-updates feature/eos-ascii-import-export feature/mcp-auth feature/mcp-group-tools feature/multi-tenant-groups feature/scene-to-look-cleanup feature/undo-redo-history 
git -C lacylights-mac branch -D feature/mcp-auth 
git -C lacylights-rpi branch -D feature/mcp-auth 
git -C lacylights-test branch -D feature/copy-fixtures-e2e-tests feature/dashboard-e2e-tests feature/eos-ascii-import-export feature/fixture-position-undo-e2e feature/mcp-auth feature/undo-redo-history fix/disable-auth-for-tests fix/e2e-page-object-locators 
git -C lacylights-terraform branch -D feature/alb-to-caddy-migration 
rm -rf lacylights-mac-wt-43
