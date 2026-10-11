# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::Runtime, observability: true do
  it "reuses identical configuration and starts a fresh identity after shutdown" do
    first = described_class.current
    expect(start_test_observability).to equal(first)

    described_class.shutdown
    second = start_test_observability
    expect(second).not_to equal(first)
    expect(second.instance_id).not_to eq(first.instance_id)
    expect(second.span_exporter.finished_spans).to be_empty
  end

  it "can be disabled without affecting the process" do
    described_class.configure(environment: "test", env: {})
    expect(described_class.current).to be_nil
    expect(OpenTelemetry.tracer_provider).to be_a(OpenTelemetry::Trace::TracerProvider)
  end

  it "fails open on invalid configuration without exposing values" do
    expect do
      expect(described_class.configure(environment: "test", env: {
        "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => "http://user:secret@invalid:4318"
      })).to be_nil
    end.to output(/Coordinator telemetry configuration unavailable \(ArgumentError\)/).to_stderr
    expect(described_class.current).to be_nil
  end

  it "isolates a rejected telemetry measurement without disabling valid work" do
    expect do
      result = described_class.safely(:test_measurement) do
        described_class.current.record(:missing_metric, 1, attributes: {})
      end
      expect(result).to be_nil
    end.to output(/Coordinator telemetry test_measurement unavailable \(KeyError\)/).to_stderr

    described_class.current.tracer.start_span("still available").finish
    expect(telemetry_spans.map(&:name)).to eq([ "still available" ])
  end

  it "creates independent provider identities and data in a forked child" do
    parent = described_class.current
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      described_class.after_fork
      child = described_class.current
      child.tracer.start_span("child").finish
      writer.write(JSON.generate(instance_id: child.instance_id, pid: child.pid, spans: child.span_exporter.finished_spans.map(&:name)))
      writer.close
      described_class.shutdown
      exit! 0
    end
    writer.close
    data = JSON.parse(reader.read)
    reader.close
    Process.wait(pid)

    expect(data).to include("pid" => pid, "spans" => [ "child" ])
    expect(data.fetch("instance_id")).not_to eq(parent.instance_id)
    expect(parent.span_exporter.finished_spans).to be_empty
    expect(described_class.current).to equal(parent)
  end
end
