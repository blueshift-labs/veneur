package statsdsink

import (
    "context"
    "errors"
    "fmt"
    "net"
    "time"

    "github.com/sirupsen/logrus"
    "github.com/stripe/veneur/v14"
    "github.com/stripe/veneur/v14/samplers"
    "github.com/stripe/veneur/v14/sinks"
    "github.com/stripe/veneur/v14/ssf"
    "github.com/stripe/veneur/v14/trace"
)

type StatsDSink struct {
    address string
    conn    net.Conn
}

// Ensure interface implementation
var _ sinks.MetricSink = &StatsDSink{}

type Config struct {
    Address string `yaml:"address"`
}

// Create implements the factory method
func Create(server *veneur.Server, name string, logger *logrus.Entry, config veneur.Config, parsedConfig sinks.MetricSinkConfig) (sinks.MetricSink, error) {
    cfg, ok := parsedConfig.(Config)
    if !ok {
        return nil, errors.New("invalid statsd sink config")
    }

    conn, err := net.Dial("udp", cfg.Address)
    if err != nil {
        return nil, err
    }

    return &StatsDSink{
        address: cfg.Address,
        conn:    conn,
    }, nil
}

// ParseConfig parses sink config map into a typed Config
func ParseConfig(name string, config interface{}) (sinks.MetricSinkConfig, error) {
    configMap, ok := config.(map[string]interface{})
    if !ok {
        return nil, fmt.Errorf("invalid config format for statsd sink")
    }
    addrRaw, ok := configMap["address"]
    if !ok {
        return nil, fmt.Errorf("missing 'address' field in statsd sink config")
    }
    addr, ok := addrRaw.(string)
    if !ok {
        return nil, fmt.Errorf("expected string for 'address' field")
    }
    return Config{Address: addr}, nil
}

func (s *StatsDSink) Name() string {
    return "statsd"
}

func (s *StatsDSink) Start(client *trace.Client) error {
    return nil
}

func (s *StatsDSink) Flush(ctx context.Context, metrics []samplers.InterMetric) error {
    for _, m := range metrics {
        var line string
        switch m.Type {
        case "counter":
            line = fmt.Sprintf("%s:%f|c", m.Name, m.Value)
        case "gauge":
            line = fmt.Sprintf("%s:%f|g", m.Name, m.Value)
        case "histogram", "timer":
            line = fmt.Sprintf("%s:%f|ms", m.Name, m.Value)
        default:
            continue
        }
        s.conn.Write([]byte(line))
    }
    return nil
}

func (s *StatsDSink) FlushOtherSamples(ctx context.Context, samples []ssf.SSFSample) error {
    return nil
}

func (s *StatsDSink) Shutdown() {
    s.conn.Close()
}

