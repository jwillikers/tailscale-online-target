#!/usr/bin/env nu

use std *

# Check if a systemd unit is active.
def "systemctl is-active" [
    unit: string # The name of the systemd unit
] {
    let result = (do { ^systemctl is-active --quiet $unit } | complete)
    if $result.exit_code == 0 {
        true
    } else {
        false
    }
}

# Start a systemd unit.
def "systemctl start" [
    unit: string # The name of the systemd unit
] {
    let result = (do { ^systemctl start $unit } | complete)
    if $result.exit_code == 0 {
        $result.stdout
    } else {
        log warning $result.stderr
    }
}

# Stop a systemd unit.
def "systemctl stop" [
    unit: string # The name of the systemd unit
] {
    let result = (do { ^systemctl stop $unit } | complete)
    if $result.exit_code == 0 {
        $result.stdout
    } else {
        log warning $result.stderr
    }
}

# Run the tailscale status command.
def "tailscale status" [
    --peers = false # Value for the --peers option passed to the tailscale status command
] {
    let result = (do { ^tailscale status $"--peers=($peers)" --json=true } | complete)
    if $result.exit_code == 0 {
        $result.stdout | from json
    } else {
        log warning $result.stderr
        null
    }
}

# Check if a Tailscale node is online.
# If no argument is provided, checks if the current node is online.
def is-online [
    node?: string # The hostname of the node to check
] {
    if not (systemctl is-active tailscaled.service) {
        return false
    }

    if not ((tailscale status --peers=false).Self.Online) {
        return false
    }

    if $node == null {
        return true
    } else {
        return ((tailscale status --peers=true).Peer | values | where HostName == $node | first | get Online)
    }
    
    false
}

# Enable or disable the appropriate Tailscale online systemd target.
# If no argument is given, activates or deactivates the tailscale-online.target systemd unit based on whether this node is online or offline.
# If a specific node is requested, activates or deactivates the tailscale-online@<node hostname>.target systemd unit based on whether the node is online or offline.
def main [
    node?: string # The hostname of the node to check
    --user # Whether to use a user target or not
] {
    let target = (
        if $node == null { 
            "tailscale-online.target"
        } else {
            $"tailscale-online@($node).target"
        }
    )

    let state_file = (
        if $node == null { 
            "/tmp/tailscale-state.json"
        } else {
            $"/tmp/tailscale-($node)-state.json"
        }
    )

    let currently_online = (is-online $node)
    let previously_online = (
        try {
            open $state_file | get online
        } catch { 
            false
        }
    )

    if $currently_online != $previously_online {
        if $currently_online {
            if $user {
                systemctl --user start $target
            } else {
                systemctl start $target
            }
        } else {
            if $user {
                systemctl --user stop $target
            } else {
                systemctl stop $target
            }
        }
        { online: $currently_online } | save --force $state_file
    }
}