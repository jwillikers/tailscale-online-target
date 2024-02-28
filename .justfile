default: install

alias f := format
alias fmt := format

format:
    just --fmt --unstable

install-nushell version="0.90.1":
    #!/usr/bin/env bash
    set -euxo pipefail
    distro=$(awk -F= '$1=="ID" { print $2 ;}' /etc/os-release)
    if [ "$distro" = "debian" ]; then
        curl --location --remote-name https://github.com/nushell/nushell/releases/download/{{ version }}/nu-{{ version }}-{{ arch() }}-unknown-linux-gnu.tar.gz
        tar --extract --file nu-{{ version }}-{{ arch() }}-unknown-linux-gnu.tar.gz
        sudo mv nu-{{ version }}-{{ arch() }}-unknown-linux-gnu/nu* /usr/local/bin
        rm --force --recursive nu-{{ version }}-{{ arch() }}-unknown-linux-gnu*
        mkdir --parents {{ config_directory() }}/nushell/
        curl --location --output {{ config_directory() }}/nushell/config.nu https://raw.githubusercontent.com/nushell/nushell/{{ version }}/crates/nu-utils/src/sample_config/default_config.nu
        curl --location --output {{ config_directory() }}/nushell/env.nu https://raw.githubusercontent.com/nushell/nushell/{{ version }}/crates/nu-utils/src/sample_config/default_env.nu
    elif [ "$distro" = "fedora" ]; then
        curl --location https://copr.fedorainfracloud.org/coprs/atim/nushell/repo/fedora/atim-nushell-fedora.repo \
            | sudo tee /etc/yum.repos.d/atim-nushell-fedora.repo
        variant=$(awk -F= '$1=="VARIANT_ID" { print $2 ;}' /etc/os-release)
        if [ "$variant" = "container" ]; then
            sudo dnf --assumeyes install nushell
        elif [ "$variant" = "iot" ] || [ "$variant" = "sericea" ]; then
            sudo rpm-ostree install nushell
        fi
    fi

install-tailscale:
    #!/usr/bin/env nu
    let distro = (open /etc/os-release | lines | par-each {|line| $line | parse "{key}={value}"} | flatten | where key == ID | first | get value)
    if $distro == "debian" {
        ^sudo apt-get --yes install lsb-release
        let codename = (^lsb_release --codename --short)
        http get $"https://pkgs.tailscale.com/stable/debian/($codename).noarmor.gpg" | ^sudo tee "/usr/share/keyrings/tailscale-archive-keyring.gpg"
        http get $"https://pkgs.tailscale.com/stable/debian/($codename).tailscale-keyring.list" | ^sudo tee "/etc/apt/sources.list.d/tailscale.list"
        ^sudo apt-get update
        ^sudo apt-get --yes install tailscale
    } else if $distro == "fedora" {
        http get "https://pkgs.tailscale.com/stable/fedora/tailscale.repo" | ^sudo tee /etc/yum.repos.d/tailscale.repo
        let variant = (open /etc/os-release | lines | par-each {|line| $line | parse "{key}={value}"} | flatten | where key == VARIANT_ID | first | get value)
        if $variant == "container" {
            ^sudo dnf --assumeyes install tailscale
        } else if $variant in ["iot", "sericea"] {
            ^sudo rpm-ostree install tailscale
        }
    }
    ^sudo systemctl enable --now tailscaled

install: install-nushell install-tailscale
    sudo cp bin/tailscale-dispatcher.nu /usr/local/bin/
    sudo cp etc/systemd/system/* /etc/systemd/system/
    sudo cp etc/systemd/user/* /etc/systemd/user/
    sudo systemctl daemon-reload
