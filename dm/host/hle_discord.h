#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize Discord Rich Presence with game name and title ID.
// Connects in the background to Discord desktop IPC.
void dm_discord_rpc_init(const char *game_name, const char *game_id);

// Dynamically update game status (from nn::friends::UserPresence::SetDescription)
void dm_discord_rpc_set_status(const char *desc);

// Commit dynamic presence update
void dm_discord_rpc_commit(void);

// Shut down Discord Rich Presence and clear activity
void dm_discord_rpc_stop(void);

#ifdef __cplusplus
}
#endif
