package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/awebai/aw/natstransport"
	"github.com/spf13/cobra"
)

var heartbeatCmd = &cobra.Command{
	Use:   "heartbeat",
	Short: "Send an explicit presence heartbeat",
	RunE: func(cmd *cobra.Command, args []string) error {
		_, sel, err := resolveClientSelection()
		if err != nil {
			return err
		}

		if nt := getNatsTransport(sel.TeamID, sel.Alias); nt != nil {
			hostname, _ := os.Hostname()
			wd, _ := os.Getwd()
			hbErr := nt.PublishHeartbeat(&natstransport.HeartbeatMessage{
				Alias:         sel.Alias,
				TeamID:        sel.TeamID,
				Hostname:      hostname,
				WorkspacePath: wd,
				Timestamp:     time.Now().UTC().Format(time.RFC3339),
			})
			if hbErr != nil {
				return fmt.Errorf("nats heartbeat: %w", hbErr)
			}
			if jsonFlag {
				printJSON(map[string]string{"status": "ok", "transport": "nats"})
			} else {
				fmt.Println("Heartbeat sent via NATS")
			}
			return nil
		}

		client, err := resolveClient()
		if err != nil {
			return err
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		resp, err := client.Heartbeat(ctx)
		if err != nil {
			return err
		}
		printJSON(resp)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(heartbeatCmd)
}
