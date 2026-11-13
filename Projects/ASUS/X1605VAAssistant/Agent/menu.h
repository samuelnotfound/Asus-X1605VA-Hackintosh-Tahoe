#pragma once
#include <stdbool.h>
#include <sys/types.h>
void AsusMenuStart(void);
void AsusMenuMute(bool muted, bool writable, float volume);
void AsusMenuMicrophoneKey(bool muted);
void AsusMenuMicrophoneUnavailable(void);
void AsusMenuMicrophoneError(void);
bool AsusMenuFirmwareKeyboardAvailable(void);
void AsusMenuKeyboardLevel(int level);
bool AsusMenuFirmwareKeyboardContinuous(void);
void AsusMenuRefreshKeyboard(void);
void AsusMenuSetKeyAccess(bool ready);
void AsusMenuSetPermissions(bool accessibility, bool ready);
void AsusMicrophoneSetEnabled(bool enabled);
bool AsusTrackpadGet(int *enabled);
bool AsusTrackpadAvailable(void);
bool AsusTrackpadSet(bool enabled);
void AsusHelperUninstall(void);
bool AsusKeyboardGet(int *percent);
bool AsusKeyboardSet(int percent, int *confirmed);
void AsusMenuRun(void);
void AsusMenuOpen(void);
void AsusMenuToggle(void);
void AsusMenuOpenExisting(void);
bool AsusFinderItemsFocused(void);
pid_t AsusFinderFrontmostPID(void);
bool AsusMenuFirmwareLauncherAvailable(void);
int AsusMenuDiagnostics(void);
