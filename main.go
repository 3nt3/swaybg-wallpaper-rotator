package main

import (
	"context"
	"errors"
	"log"
	"os"
	"os/exec"
	"time"

	"math/rand"

	"3nt3.de/swaybg-wallpaper-rotator/v2/config"
	"github.com/BurntSushi/toml"
	"github.com/urfave/cli/v3"
)

func main() {
	cmd := &cli.Command{
		Name:  "swaybg-wallpaper-rotator",
		Usage: "A wallpaper rotator for SwayBG",
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:     "config",
				Aliases:  []string{"c"},
				Usage:    "Path to the configuration file",
				Required: true,
			},
		},
		Action: func(context context.Context, cmd *cli.Command) error {
			/* Load config */
			config := &config.Config{}

			configPath := cmd.String("config")
			if configPath != "" {
				if _, err := toml.DecodeFile(configPath, config); err != nil {
					log.Fatalf("Failed to load config file: %v", err)
				}
			}

			log.Printf("Starting wallpaper rotator with config: %+v", config)

			for {
				wp, err := chooseWallpaper(config)
				if err != nil {
					log.Fatalf("Failed to choose wallpaper: %v", err)
				}

				log.Printf("Setting wallpaper to: %s", wp)

				// set wallpaper using swaybg
				exec.Command("pkill", "swaybg") // kill existing swaybg instances
				go setWallpaper(config.WallpaperDir + "/" + wp)

				log.Printf("Waiting for %s before next rotation", config.RotationInterval.String())
				time.Sleep(*config.RotationInterval)
			}
		},
	}

	if err := cmd.Run(context.Background(), os.Args); err != nil {
		log.Fatal(err)
	}

}

func chooseWallpaper(config *config.Config) (string, error) {
	// get files in directory
	dirEntry, err := os.ReadDir(config.WallpaperDir)
	if err != nil {
		return "", err
	}

	// multiply files with optional weight
	filesWeighted := []string{}
	for _, entry := range dirEntry {
		if weight, ok := config.Weights[entry.Name()]; ok {
			for i := 0; i < weight; i++ {
				filesWeighted = append(filesWeighted, entry.Name())
			}
		} else {
			filesWeighted = append(filesWeighted, entry.Name())
		}
	}

	// choose random file
	if len(filesWeighted) == 0 {
		return "", errors.New("no wallpapers found in directory")
	}

	rand.NewSource(time.Now().UnixNano())
	randomIndex := rand.Intn(len(filesWeighted))

	return filesWeighted[randomIndex], nil
}

func setWallpaper(wallpaperPath string) error {
	cmd := exec.Command("swaybg", "-i", wallpaperPath, "-m", "fill", "-o", "*")
	return cmd.Run()
}

func waitInterval(interval string) error {
	duration, err := time.ParseDuration(interval)
	if err != nil {
		return err
	}
	time.Sleep(duration)
	return nil
}
