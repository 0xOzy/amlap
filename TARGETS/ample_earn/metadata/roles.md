# Roles

## Owner (multi-sig)
- Upgrade contracts (proxy)
- Pause protocol
- Set fees & fee recipient
- Transfer/renounce ownership

## Guardian
- Cancel timelocked actions (circuit-breaker)
- Emergency response

## Curator
- Add/remove strategies
- Set per-strategy caps
- Initiate forced removals (timelocked)

## Allocator
- Manage supply/withdraw queues
- Trigger reallocations within caps

## Oracle Admin
- Update oracle configuration (Euler-level)

## Risks
- Centralised upgrade authority (Owner can upgrade proxy)
- Guardian can block legitimate actions
- Curator can remove profitable strategies
