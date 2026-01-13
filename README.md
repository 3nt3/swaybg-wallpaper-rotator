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
