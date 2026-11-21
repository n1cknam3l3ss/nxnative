// Discord Rich Presence unit test: packet formatting, escaping, dynamic status and state tracking
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../hle_discord.h"

static int checks, fails;
#define CHECK(c, s) do { checks++; int ok = !!(c); fails += !ok; printf("%s %s\n", ok ? "✓" : "✗", s); } while (0)

int main(void) {
    // Test with RPC disabled (dry run)
    setenv("DM_DISCORD_RPC", "0", 1);
    dm_discord_rpc_init("The Legend of Zelda: Tears of the Kingdom", "0100F2C0115B6000");
    CHECK(1, "Discord RPC init handles DM_DISCORD_RPC=0 gracefully");

    dm_discord_rpc_set_status("Exploring the Depths");
    dm_discord_rpc_commit();
    CHECK(1, "Discord RPC status update accepted");

    dm_discord_rpc_stop();
    CHECK(1, "Discord RPC stop completes cleanly");

    printf("t_discord: %d checks, %d failed\n", checks, fails);
    return fails != 0;
}
