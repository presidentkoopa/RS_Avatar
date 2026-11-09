// Included from RS_Avatar's zscript.txt (version 4.14 there) since 2026-10-27.

// Body-anchored holsters. Split out of RS_Main 2026-08-16 -- same author,
// same engine (UZDXREMA/DoomXR), no genericization needed.
//
// REAL DEPENDENCIES, this pk3 is not standalone-playable without them:
//   - SOME weapon-content pack must be loaded: RS_HolsterProp borrows a
//     stored weapon's model via A_ChangeModel(w.GetClassName()), which
//     resolves against THAT WEAPON'S OWN MODELDEF block, wherever it lives.
//     Not RS_Main specifically -- confirmed against RS_Lance's LNC_Lance (a
//     plain Weapon in its own separate pk3) working identically. Store/draw/
//     claim all work with no weapon pack loaded at all; only the visible
//     model needs one, and it does not care which pack supplies it.
//   - The engine (UZDXREMA/DoomXR) fields this drives are native, not stock
//     GZDoom: HmdPos/HmdYaw/HmdPitch/HmdRoll, HolsterClaimMain/Off,
//     GripContextMain/Off, VRTurnYaw, StabilizeReach, ReadyWeapon/
//     OffhandWeapon and MoveWeaponToHand's dual-wield hand routing, and the
//     natives level.VRHaptic / level.GetModelOrientationHint /
//     level.GetModelOffsetHint / level.GetModelBoundsHint /
//     level.GetModelWorldOffset. None of this runs on stock GZDoom or on
//     QuestZDoom proper -- and none of it is any specific weapon pack's,
//     it is all engine-level.
//
// RS_HolsterManager must ALSO be in AddEventHandlers -- MAPINFO.holsters does it.

#include "zscript/holsters/RS_HolsterProp.zs"
#include "zscript/holsters/RS_Holsters.zs"
