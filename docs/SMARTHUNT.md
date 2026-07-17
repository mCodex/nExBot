# Tactical Intelligence

Unified session analytics, monster intelligence, targeting history, resources, routes, replay, and pipeline health.

## Navigation

Open the `Tactical Intelligence` window from the Main tab.

## API

```lua
nExBot.TacticalIntelligence:startSession()
nExBot.TacticalIntelligence:stopSession()
nExBot.TacticalIntelligence:isSessionActive()
nExBot.TacticalIntelligence:getOverviewSnapshot()
nExBot.TacticalIntelligence:getHuntSnapshot()
nExBot.TacticalIntelligence:getMonsterProfilesSnapshot()
nExBot.TacticalIntelligence:getModelSnapshot()
nExBot.TacticalIntelligence:getPipelineSnapshot()
nExBot.TacticalIntelligence:getDiagnosticsSnapshot()
nExBot.TacticalIntelligence:subscribe(listener)
nExBot.TacticalIntelligence:unsubscribe(token)
```

## Reporting

Source modules should publish canonical intelligence events or call the facade directly. Legacy intelligence entry points are retired.

## Troubleshooting

- No data: start a hunting session and confirm the source modules are loaded.
- Empty models: the pipeline has not seen enough evidence yet.
- Stale UI: reopen the Tactical Intelligence window to force a refresh.
