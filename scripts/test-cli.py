#!/usr/bin/env python3
"""Real CLI smoke tests. Requires an Apple Silicon Mac with GPU/WebKit access."""
import functools
import http.server
import pathlib
import subprocess
import sys
import tempfile
import threading
import wave

binary = pathlib.Path(sys.argv[1]).resolve()

def run(*args, input=None, ok=True):
    p = subprocess.run([str(binary), *args], input=input, text=True, capture_output=True, timeout=90)
    assert (p.returncode == 0) == ok, (args, p.returncode, p.stdout, p.stderr)
    return p

with tempfile.TemporaryDirectory(prefix='pagehum-smoke-') as directory:
    root = pathlib.Path(directory)
    # Running from an unrelated working directory catches resource path assumptions.
    import os
    os.chdir(root)
    assert 'generate' in run('--help').stdout
    for args in [('--text', 'Hello', '--stdin'), ('--text', '  '), ('--url', 'file:///tmp/a'),
                 ('--text', 'Hello', '--quality', 'invalid'), ('--text', 'Hello', '--voice', 'zz_unknown')]:
        run('generate', *args, '-o', str(root / 'invalid.m4a'), ok=False)
        assert not (root / 'invalid.m4a').exists()
    voices = run('voices').stdout.splitlines()
    assert 'af_heart' in voices and all(' ' not in v and '.npy' not in v for v in voices)

    wav = root / 'stdin.wav'
    p = run('generate', '--stdin', '-o', str(wav), input='Hello there. This recording was generated from standard input.')
    assert p.stdout.strip() == str(wav)
    with wave.open(str(wav)) as f:
        assert (f.getnchannels(), f.getframerate(), f.getsampwidth()) == (1, 24000, 2)
        assert f.getnframes() > 24000
        assert any(f.readframes(f.getnframes()))
    original = wav.read_bytes()
    run('generate', '--text', 'Do not overwrite this.', '-o', str(wav), ok=False)
    assert wav.read_bytes() == original
    run('generate', '--text', 'Invalid voice.', '--voice', 'af_missing', '--force', '-o', str(wav), ok=False)
    assert wav.read_bytes() == original
    run('generate', '--text', 'Replacement audio.', '--force', '-o', str(wav))
    assert wav.read_bytes() != original

    source = root / 'notes.txt'
    source.write_text('Clear speech, saved to a compressed audio file. This is a second sentence.')
    for quality in ('compact', 'balanced', 'high'):
        out = root / f'{quality}.m4a'
        run('generate', '--file', str(source), '--quality', quality, '-o', str(out))
        info = subprocess.check_output(['afinfo', str(out)], text=True)
        assert '24000 Hz, aac' in info and '1 ch' in info
        rate_line = next(line.strip() for line in info.splitlines() if 'bit rate:' in line)
        measured = float(rate_line.split(':')[1].strip().split()[0])
        target = {'compact': 32000, 'balanced': 48000, 'high': 64000}[quality]
        assert 0.75 * target <= measured <= 1.25 * target, (quality, measured)
        print(quality, rate_line)
    run('generate', '--text', 'Hello from text input.', '-o', str(root / 'text.m4a'))

    article = '<html><head><title>CLI reader test</title></head><body><nav>Navigation</nav><article><h1>A local article</h1>'
    article += '<p>' + ('This article checks that a web page can become a spoken audio file. ' * 5) + '</p>'
    article += '</article></body></html>'
    (root / 'article.html').write_text(article)
    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args): pass
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(root)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        out = root / 'article.m4a'
        p = run('generate', '--url', f'http://127.0.0.1:{server.server_port}/article.html', '-o', str(out))
        assert out.stat().st_size > 1000 and 'Article:' in p.stderr
    finally:
        server.shutdown()
        server.server_close()
    assert not list(root.glob('.pagehum-*')), 'Temporary output leaked'
print('CLI smoke tests passed: inputs, presets, audio, resources, errors, overwrite, URL extraction.')
