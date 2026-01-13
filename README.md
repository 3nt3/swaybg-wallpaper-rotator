# SwayBG Wallpaper Rotator

## Usage
```sh
swaybg-wallpaper-rotator -c /path/to/config.toml
```

## Configuration

```toml
wallpaper_dir = "/home/ente/Pictures/wallpapers"
rotation_interval = "10s" # must be parseable by time.Duration

[weights]
"IMG_6714.JPG" = 5 # this makes this image five times more likely to be chosen
```

## Systemd Service

Use this instead of `swaybg.service`

```ini
[Unit]
PartOf=graphical-session.target
After=graphical-session.target
Requisite=graphical-session.target

[Service]
ExecStart=/home/ente/src/3nt3/swaybg-wallpaper-rotator/swaybg-wallpaper-rotato -c /home/ente/.config/swaybg-wallpaper-rotator.toml
Restart=on-failure
```
