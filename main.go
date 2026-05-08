package main

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/containernetworking/cni/pkg/invoke"
	"github.com/containernetworking/cni/pkg/skel"
	"github.com/containernetworking/cni/pkg/types"
	"github.com/containernetworking/cni/pkg/version"
)

type PluginConf struct {
	types.NetConf

	DelegateType string `json:"delegateType"`
	Subnet       string `json:"subnet"`
	Bridge       string `json:"bridge,omitempty"`
}

func parseConf(stdin []byte) (*PluginConf, error) {
	c := &PluginConf{}
	if err := json.Unmarshal(stdin, c); err != nil {
		return nil, fmt.Errorf("parse netconf: %w", err)
	}
	if c.DelegateType == "" {
		c.DelegateType = "ptp"
	}
	if c.Subnet == "" {
		return nil, fmt.Errorf("subnet is required")
	}
	return c, nil
}

func buildDelegate(c *PluginConf) ([]byte, error) {
	d := map[string]any{
		"cniVersion": c.CNIVersion,
		"name":       c.Name,
		"type":       c.DelegateType,
		"ipam": map[string]any{
			"type":   "host-local",
			"subnet": c.Subnet,
			"routes": []map[string]string{{"dst": "0.0.0.0/0"}},
		},
	}
	if c.DelegateType == "bridge" {
		d["isGateway"] = true
		d["ipMasq"] = true
		if c.Bridge != "" {
			d["bridge"] = c.Bridge
		}
	}
	return json.Marshal(d)
}

func cmdAdd(args *skel.CmdArgs) error {
	c, err := parseConf(args.StdinData)
	if err != nil {
		return err
	}
	delegateBytes, err := buildDelegate(c)
	if err != nil {
		return err
	}

	result, err := invoke.DelegateAdd(context.TODO(), c.DelegateType, delegateBytes, nil)
	if err != nil {
		return fmt.Errorf("delegate add %q: %w", c.DelegateType, err)
	}

	return types.PrintResult(result, c.CNIVersion)
}

func cmdDel(args *skel.CmdArgs) error {
	c, err := parseConf(args.StdinData)
	if err != nil {
		return err
	}
	delegateBytes, err := buildDelegate(c)
	if err != nil {
		return err
	}
	if err := invoke.DelegateDel(context.TODO(), c.DelegateType, delegateBytes, nil); err != nil {
		return fmt.Errorf("delegate del %q: %w", c.DelegateType, err)
	}
	return nil
}

func cmdCheck(args *skel.CmdArgs) error {
	c, err := parseConf(args.StdinData)
	if err != nil {
		return err
	}
	delegateBytes, err := buildDelegate(c)
	if err != nil {
		return err
	}
	return invoke.DelegateCheck(context.TODO(), c.DelegateType, delegateBytes, nil)
}

func main() {
	skel.PluginMainFuncs(
		skel.CNIFuncs{Add: cmdAdd, Del: cmdDel, Check: cmdCheck},
		version.All,
		"sandbox-cni: a thin delegating CNI plugin",
	)
}
