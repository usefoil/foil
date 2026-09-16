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
  executable = ENV['FOIL_RUNTIME_ARCH'] == 'x86_64' ? ['/usr/bin/arch', '-x86_64', runtime] : [runtime]
  pid = Process.spawn({'FOIL_SESSION_ID'=>session, 'FOIL_MODEL_SHA256'=>hash, 'FOIL_MANAGED_TOKEN'=>token}, *executable,
    '-m', model, '--host', '127.0.0.1', '--port', port.to_s, '--request-path', "/#{token}",
    '--inference-path', '/v1/audio/transcriptions', '--public', dir,
    :in=>read_pipe, :out=>File::NULL, :err=>File::NULL)
  read_pipe.close
  begin
    response = nil
    300.times do
      begin
        http = Net::HTTP.new('transcribe.foil.localhost', port, nil)
        http.open_timeout = 1
        http.read_timeout = 1
        response = http.get("/#{token}/health")
        break if response.code == '200'
      rescue SystemCallError, Timeout::Error
      end
      sleep 0.1
    end
    raise 'Runtime did not become ready' unless response && response.code == '200'
    expected = {'status'=>'ok', 'service'=>'foil-whisper', 'session'=>session, 'model_sha256'=>hash, 'pid'=>pid}
    raise 'Health did not prove current child and model identity' unless JSON.parse(response.body) == expected
    ['/health', '/wrong/health', "/#{token}/load", '/'].each do |path|
      status = Net::HTTP.new('transcribe.foil.localhost', port, nil).get(path).code
      raise 'Unauthorized route accepted' unless ['403', '404'].include?(status)
    end
    speech = File.join(dir, 'speech.aiff')
    wav = File.join(dir, 'speech.wav')
    raise 'Speech fixture generation failed' unless system('/usr/bin/say', '-o', speech, 'The quick brown fox jumps over the lazy dog.')
    raise 'Speech fixture conversion failed' unless system('/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', speech, wav)
    boundary = SecureRandom.hex(16)
    body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".b
    body << File.binread(wav) << "\r\n--#{boundary}\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n--#{boundary}--\r\n"
    request = Net::HTTP::Post.new("/#{token}/v1/audio/transcriptions")
    request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    request.body = body
    http = Net::HTTP.new('transcribe.foil.localhost', port, nil)
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
    puts 'PASS: exact identity, unauthorized routes, real transcript, parent EOF'
  ensure
    write_pipe.close unless write_pipe.closed?
    if pid
      Process.kill('KILL', pid) rescue nil
      Process.waitpid(pid) rescue nil
    end
  end
end
RUBY
