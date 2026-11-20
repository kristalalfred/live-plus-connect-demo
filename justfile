# The demo pins the open-connect bench's defaults, so `just run` works against a
# bench that is already up with no configuration of its own.
connect_dir := env("OPEN_CONNECT_DIR", home_directory() / "git" / "open-connect")
addr      := env("GREENROOM_ADDR", "127.0.0.1:8090")
public    := env("GREENROOM_PUBLIC_URL", "http://localhost:8090")
hook_url  := "http://host.docker.internal:8090/api/connect/events"

export GREENROOM_ADDR          := addr
export GREENROOM_PUBLIC_URL    := public
export GREENROOM_WEBHOOK_TOKEN := env("GREENROOM_WEBHOOK_TOKEN", "bench-webhook-token")
export GREENROOM_SIGNING_KEY   := env("GREENROOM_SIGNING_KEY", "bench-greenroom-key")
export CONNECT_NORTHBOUND_URL    := env("CONNECT_NORTHBOUND_URL", "http://localhost:29080")
export CONNECT_NORTHBOUND_TOKEN  := env("CONNECT_NORTHBOUND_TOKEN", "bench-northbound-token")
export CONNECT_SOUTHBOUND_URL    := env("CONNECT_SOUTHBOUND_URL", "http://localhost:29081")
export CONNECT_SOUTHBOUND_TOKEN  := env("CONNECT_SOUTHBOUND_TOKEN", "bench-southbound-token")
export OPEN_LIVE_URL           := env("OPEN_LIVE_URL", "http://localhost:3000")

[doc("Run the gateway, serving the pages from assets/ so an edit needs no rebuild.")]
run *ARGS:
    GREENROOM_ASSETS={{justfile_directory()}}/assets cargo run --quiet -- {{ARGS}}

[doc("Run the release build with the pages baked in.")]
serve *ARGS:
    cargo run --quiet --release -- {{ARGS}}

build:
    cargo build --release

test:
    cargo test --quiet

check:
    cargo clippy --all-targets -- -D warnings
    cargo test --quiet
    node --check assets/guest.js
    node --check assets/operator.js

connect_services := "controller northbound southbound adapter-1 adapter-2 adapter-3"

# Rebuilt, not just recreated: the bench image is only as new as the last
# `just bench up`, and a controller predating open-connect's webhook commit
# accepts the variable and emits nothing. Every connect service shares that one
# image, so they are recreated together — a new controller serves desired hops
# an older adapter cannot decode.
[doc("Point the bench controller's node lifecycle webhooks at this gateway.")]
hook:
    cd {{connect_dir}}/bench && docker compose build {{connect_services}}
    cd {{connect_dir}}/bench && CONNECT_WEBHOOK_URL={{hook_url}} docker compose up -d {{connect_services}}
    @echo "controller now delivers node events to {{hook_url}}"

[doc("Send the bench controller's webhooks back to `just bench hook-sink`.")]
unhook:
    cd {{connect_dir}}/bench && docker compose up -d --force-recreate controller

[doc("What the three systems say about each other right now.")]
status:
    @echo "— greenroom"
    @curl -sf {{public}}/health || echo "  down"
    @echo "\n— connect nodes"
    @curl -sf -H "Authorization: Bearer $CONNECT_SOUTHBOUND_TOKEN" $CONNECT_SOUTHBOUND_URL/v1/nodes \
        | python3 -c 'import json,sys; [print(" ", n["id"], n["status"]) for n in json.load(sys.stdin)]' || echo "  down"
    @echo "— connect streams"
    @curl -sf -H "Authorization: Bearer $CONNECT_NORTHBOUND_TOKEN" $CONNECT_NORTHBOUND_URL/v1/status \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(" ", s["name"], s["status"]) for s in d.get("streams",[])]' || echo "  down"
    @echo "— open-live sources from connect"
    @curl -sf $OPEN_LIVE_URL/api/v1/sources \
        | python3 -c 'import json,sys; [print(" ", s["id"], s.get("status")) for s in json.load(sys.stdin) if (s.get("provider") or {}).get("id")=="connect"]' || echo "  down"

[doc("Forget every seat. Revoke through the UI instead unless the state file is stale.")]
reset:
    rm -f greenroom-state.json greenroom-state.json.tmp
