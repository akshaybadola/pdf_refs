import os
import sys
import argparse


from .const import __version__


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-threaded", dest="threaded", action="store_false",
                        help="Whether flask server should be threaded or not")
    parser.add_argument("--port", "-p", type=int, default=9999,
                        help="Port to bind to the python server")
    parser.add_argument("--proxy-port", dest="proxy_port", type=int, default=0,
                        help="HTTP proxy server port for method 'fetch_proxy'")
    parser.add_argument("--proxy-everything", dest="proxy_everything", action="store_true",
                        help="Should we proxy all requests?")
    parser.add_argument("--proxy-everything-port", dest="proxy_everything_port",
                        type=int, default=0,
                        help="HTTP proxy server port if proxy_everything is given")
    parser.add_argument("--data-dir", "-d", dest="data_dir", type=str,
                        default=os.path.expanduser("~"),
                        help="Semantic Scholar cache directory")
    parser.add_argument("--batch-size", "-b", dest="batch_size", type=int, default=16,
                        help="Simultaneous connections to DBLP")
    parser.add_argument("--verbosity", "-v", type=str, default="info",
                        help="Verbosity level. One of [error, info, debug]")
    parser.add_argument("--version", action="store_true",
                        help="Print version and exit.")
    args = parser.parse_args()
    if args.version:
        print(f"ref-man-server version {__version__}")
        sys.exit(0)
    from .server import Server
    server = Server(args)
    server.run()