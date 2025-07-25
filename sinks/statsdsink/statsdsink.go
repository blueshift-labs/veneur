package statsdsink

import (
	"context"
	"fmt"
	"net"

	"github.com/sirupsen/logrus"
	"github.com/stripe/veneur/v14"
	"github.com/stripe/veneur/v14/samplers"
	"github.com/stripe/veneur/v14/sinks"
	"github.com/stripe/veneur/v14/ssf"
	"github.com/stripe/veneur/v14/trace"
	"github.com/stripe/veneur/v14/util"
)

type Config struct {
	Address string `yaml:"address"`
}

type StatsDSink struct {
	address string
	conn    net.Conn
}

var _ sinks.MetricSink = &StatsDSink{}

func (s *StatsDSink) Name() string {
	return "statsd"
}

func (s *StatsDSink) Start(_ *trace.Client) error {
	return nil
}

func (s *StatsDSink) Flush(ctx context.Context, metrics []samplers.InterMetric) error {
	for _, m := range metrics {
		var line string
		switch m.Type {
		case samplers.CounterMetric:
			line = fmt.Sprintf("%s:%f|c", m.Name, m.Value)
		case samplers.GaugeMetric:
			line = fmt.Sprintf("%s:%f|g", m.Name, m.Value)
		default:
			// Skip unsupported metric types (e.g., status, histogram)
			continue
		}
		_, _ = s.conn.Write([]byte(line))
	}
	return nil
}

func (s *StatsDSink) FlushOtherSamples(ctx context.Context, samples []ssf.SSFSample) {
	// no-op
}

func (s *StatsDSink) Shutdown() {
	_ = s.conn.Close()
}

func ParseConfig(name string, config interface{}) (veneur.MetricSinkConfig, error) {
  var statsdConfig Config
  err := util.DecodeConfig(name, config, &statsdConfig)
  if err != nil {
    return nil, fmt.Errorf("failed to decode statsd sink config: %w", err)
  }

  if statsdConfig.Address == "" {
    return nil, fmt.Errorf("statsd sink requires 'address' to be set")
  }

  return &statsdConfig, nil
}

func Create(
	_ *veneur.Server,
	_ string,
	_ *logrus.Entry,
	_ veneur.Config,
	cfg veneur.MetricSinkConfig,
) (sinks.MetricSink, error) {
	conf := cfg.(*Config)
	conn, err := net.Dial("udp", conf.Address)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to statsd address: %w", err)
	}
	return &StatsDSink{
		address: conf.Address,
		conn:    conn,
	}, nil
}

