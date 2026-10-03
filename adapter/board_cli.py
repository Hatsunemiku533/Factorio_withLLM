"""Local board tool for Stellan. This is not exposed to Mira."""

import argparse
import json
import sys

import board_store


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    post = commands.add_parser("post")
    post.add_argument("--to", required=True, choices=["mira", "all"])
    post.add_argument("text")
    commands.add_parser("list")
    unread = commands.add_parser("unread")
    unread.add_argument("--for", dest="agent", default="stellan")
    args = parser.parse_args()
    if args.command == "post":
        result = board_store.post("stellan", args.to, args.text)
    elif args.command == "list":
        result = board_store.recent()
    else:
        result = board_store.read_for(args.agent, mark_delivered=False)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
