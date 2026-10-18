#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  --app) runtime="$2/Contents/Helpers/whisper-server" ;;
  --runtime) runtime="$2" ;;
  *) echo 'Usage: test-managed-whisper-runtime.sh --app APP | --runtime HELPER' >&2; exit 2 ;;
esac
ruby - "$runtime" "$PWD/.research/managed-runtime/models/ggml-tiny.en.bin" <<'RUBY'
require 'socket'
require 'net/http'
require 'json'
require 'securerandom'
require 'tmpdir'
require 'digest'
runtime, model = ARGV
hash = '921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f'
raise 'Fixture integrity failed' unless File.size(model) == 77704715 && Digest::SHA256.file(model).hexdigest == hash
Dir.mktmpdir('foil-runtime-', File.join(Dir.pwd, '.research')) do |dir|
  reservation = TCPServer.new('127.0.0.1', 0)
  port = reservation.addr[1]
  reservation.close
  token = SecureRandom.hex(32)
  session = SecureRandom.uuid
  read_pipe, write_pipe = IO.pipe
  require_precompiled = ENV['FOIL_REQUIRE_PRECOMPILED_METAL'] == '1'
  shader_read, shader_write = IO.pipe if require_precompiled
  precompiled_used = false
  metal_graph_used = false
  shader_reader = nil
  executable = ENV['FOIL_RUNTIME_ARCH'] == 'x86_64' ? ['/usr/bin/arch', '-x86_64', runtime] : [runtime]
  pid = Process.spawn({'FOIL_SESSION_ID'=>session, 'FOIL_MODEL_SHA256'=>hash, 'FOIL_MANAGED_TOKEN'=>token,
    'FOIL_MANAGED_STARTUP_TRACE'=>(require_precompiled ? '1' : nil)}, *executable,
    '-m', model, '--host', '127.0.0.1', '--port', port.to_s, '--request-path', "/#{token}",
    '--inference-path', '/v1/audio/transcriptions', '--public', dir,
    :in=>read_pipe, :out=>File::NULL, :err=>(shader_write || File::NULL))
  read_pipe.close
  shader_write.close if shader_write
  if require_precompiled
    shader_reader = Thread.new do
      shader_read.each_line("\n", 4096) do |line|
        precompiled_used = true if line == "ggml_metal_library_init: loaded embedded precompiled Metal library\n"
        metal_graph_used = true if line == "FOIL_STARTUP_STAGE metal_graph_submitted\n"
      end
    end
  end
  # Keep the helper's virtual Host while matching the app's numeric loopback route.
  # Do not depend on the OS resolving arbitrary .localhost subdomains.
  def managed_http(port)
    Net::HTTP.new('127.0.0.1', port, nil)
  end
  def host_header(port)
    {'Host' => "transcribe.foil.localhost:#{port}"}
  end
  begin
    response = nil
    300.times do
      begin
        http = managed_http(port)
        http.open_timeout = 1
        http.read_timeout = 1
        response = http.get("/#{token}/health", host_header(port))
        break if response.code == '200'
      rescue SystemCallError, Timeout::Error
      end
      sleep 0.1
    end
    raise 'Runtime did not become ready' unless response && response.code == '200'
    expected = {'status'=>'ok', 'service'=>'foil-whisper', 'session'=>session, 'model_sha256'=>hash, 'pid'=>pid}
    raise 'Health did not prove current child and model identity' unless JSON.parse(response.body) == expected
    ['/health', '/wrong/health', "/#{token}/load", '/'].each do |path|
      status = managed_http(port).get(path, host_header(port)).code
      raise 'Unauthorized route accepted' unless ['403', '404'].include?(status)
    end
    speech = File.join(dir, 'speech.aiff')
    wav = File.join(dir, 'speech.wav')
    raise 'Speech fixture generation failed' unless system('/usr/bin/say', '-o', speech, 'The quick brown fox jumps over the lazy dog.')
    raise 'Speech fixture conversion failed' unless system('/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', speech, wav)
    boundary = SecureRandom.hex(16)
    body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".b
    body << File.binread(wav) << "\r\n--#{boundary}\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n--#{boundary}--\r\n"
    request = Net::HTTP::Post.new("/#{token}/v1/audio/transcriptions", host_header(port))
    request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    request.body = body
    http = managed_http(port)
    http.read_timeout = 120
    transcript_response = http.request(request)
    raise 'Real transcription failed' unless transcript_response.code == '200'
    transcript = JSON.parse(transcript_response.body).fetch('text')
    raise 'Synthetic speech was not transcribed correctly' unless transcript.downcase.include?('quick brown fox')
    puts "Synthetic transcript: #{transcript.strip}"
    write_pipe.close
    deadline = Time.now + 5
    while !Process.waitpid(pid, Process::WNOHANG)
      raise 'Parent EOF did not terminate owned child' if Time.now > deadline
      sleep 0.05
    end
    pid = nil
    if require_precompiled
      raise 'Shader diagnostic pipe did not close' unless shader_reader.join(5)
      raise 'Transcription did not use embedded precompiled Metal' unless precompiled_used
      raise 'Transcription did not submit a Metal graph' unless metal_graph_used
      puts 'PASS: embedded precompiled Metal loaded and a nonempty Metal graph submitted'
    end
    puts 'PASS: exact identity, unauthorized routes, real transcript, parent EOF'
  ensure
    write_pipe.close unless write_pipe.closed?
    if pid
      Process.kill('KILL', pid) rescue nil
      Process.waitpid(pid) rescue nil
    end
    shader_reader.join(5) if shader_reader
    shader_read.close if shader_read && !shader_read.closed?
  end
end
RUBY
