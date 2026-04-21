#!/usr/bin/env python3
"""Send an email via AWS SES."""

import argparse
import os
import sys

import boto3
from botocore.exceptions import ClientError

# Ignore any inherited AWS_PROFILE so boto3 falls back to the instance role
# credentials from IMDS instead of failing on a missing profile config.
os.environ.pop("AWS_PROFILE", None)
os.environ.pop("AWS_DEFAULT_PROFILE", None)

DEFAULT_FROM = "aleks@infrahouse.com"


def parse_args():
    parser = argparse.ArgumentParser(description="Send an email via AWS SES.")
    parser.add_argument(
        "--to",
        nargs="+",
        required=True,
        metavar="ADDRESS",
        help="One or more recipient addresses.",
    )
    parser.add_argument("--subject", required=True, help="Email subject.")
    parser.add_argument(
        "--from",
        dest="from_address",
        default=DEFAULT_FROM,
        help=f"From address (default: {DEFAULT_FROM}).",
    )
    parser.add_argument(
        "--cc",
        nargs="+",
        default=[],
        metavar="ADDRESS",
        help="Optional CC addresses.",
    )
    parser.add_argument(
        "--bcc",
        nargs="+",
        default=[],
        metavar="ADDRESS",
        help="Optional BCC addresses.",
    )
    parser.add_argument("--region", help="AWS region (defaults to boto3 resolution).")

    body_group = parser.add_mutually_exclusive_group(required=True)
    body_group.add_argument("--body", help="Inline message body.")
    body_group.add_argument(
        "--body-file",
        type=argparse.FileType("r", encoding="utf-8"),
        help="Read message body from file ('-' for stdin).",
    )
    parser.add_argument(
        "--html",
        action="store_true",
        help="Treat body as HTML instead of plain text.",
    )

    return parser.parse_args()


def main():
    args = parse_args()

    body = args.body if args.body is not None else args.body_file.read()
    body_key = "Html" if args.html else "Text"

    client = boto3.client("ses", region_name=args.region) if args.region else boto3.client("ses")

    destination = {"ToAddresses": args.to}
    if args.cc:
        destination["CcAddresses"] = args.cc
    if args.bcc:
        destination["BccAddresses"] = args.bcc

    try:
        response = client.send_email(
            Source=args.from_address,
            Destination=destination,
            Message={
                "Subject": {"Data": args.subject, "Charset": "UTF-8"},
                "Body": {body_key: {"Data": body, "Charset": "UTF-8"}},
            },
        )
    except ClientError as exc:
        print(f"SES send failed: {exc}", file=sys.stderr)
        sys.exit(1)

    print(response["MessageId"])


if __name__ == "__main__":
    main()
