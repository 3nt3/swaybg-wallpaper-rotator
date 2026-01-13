package config

import "time"

type Config struct {
	WallpaperDir     string         `toml:"wallpaper_dir"`
	RotationInterval *time.Duration `toml:"rotation_interval"` // in minutes
	Weights          map[string]int `toml:"weights"`
}
