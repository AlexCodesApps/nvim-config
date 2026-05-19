import sys
import io
import ast
from contextlib import redirect_stdout, redirect_stderr

def eprint(*kwargs):
    print(*kwargs, file = sys.stderr)

def send_response(payload: bytes):
    header = len(payload).to_bytes(8, 'big')
    sys.stdout.buffer.write(header)
    sys.stdout.buffer.write(payload)
    sys.stdout.buffer.flush()

while True:
    payload_len_bytes = sys.stdin.buffer.read(8)
    if len(payload_len_bytes) == 0:
        break
    if len(payload_len_bytes) < 8:
        send_response(b'error: unexpected EOF while reading header\n')
        break
    payload_len = int.from_bytes(payload_len_bytes, 'big')
    payload = sys.stdin.read(payload_len)
    if len(payload) != payload_len:
        resp = (
                'error: EOF while reading payload\n'
                f'expected {payload_len} bytes, got {len(payload)} bytes\n'
        ).encode()
        send_response(resp)
        break
    with io.StringIO() as buf, redirect_stdout(buf), redirect_stderr(buf):
        try:
            tree = ast.parse(payload)
            if len(tree.body) > 0:
                last = tree.body[-1]
                if isinstance(last, ast.Expr):
                    printfn = ast.Name('print', ast.Load())
                    expr = ast.Call(printfn, [last.value])
                    tree.body[-1] = ast.Expr(expr)
                    ast.fix_missing_locations(tree)
                code = compile(tree, '<repl>', 'exec')
                exec(code)
        except Exception as err:
            eprint(str(err))
        output = buf.getvalue()
    send_response(output.encode())
