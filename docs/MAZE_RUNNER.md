# Maze Runner — Current Scope

The 2.1.0 source includes an optional, partial Maze Runner controller. It is not a complete implementation of every original map mechanic.

## Before enabling

- Import the intended map as a separate Paper world.
- Configure the Glade centre in-game with /maze setglade.
- Review the safe-zone half-size and gameplay radius.
- Keep the central Maze Runner module disabled until the map has been imported and settings have been verified.
- Test on a disposable world first.

The controller stores its runtime settings in the plugin data directory, not in Git. The controller should not be enabled against an unverified world or a live production map.

## Implemented first-stage behavior

- Up to eight plugin-managed spider entities named Grievers can spawn at night near eligible players within the configured maze radius but outside the Glade.
- The safe Glade prevents managed Grievers from damaging players inside it.
- Killing a managed Griever can drop a compass item named for the Griever.
- Managed Grievers are removed during daytime and when the mode is disabled or its control-plane state is stale.
- Persistent entity metadata limits cleanup to entities created by this mode.

## Not implemented in this stage

The current controller does not implement the complete gate opening/closing timer, Narrows passage changes, eight unique sections, wool-domain progression, or monument colour validation. These require verified map coordinates, imported-world testing, and a separate mechanics implementation.

Do not infer complete Maze Runner parity from the presence of the controller or the /maze command. No production world import, wipe, or automatic mode activation is performed by the repository.
