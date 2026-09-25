#!/usr/bin/env python3

import argparse
import json
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlparse


SECLISTS = Path("/usr/share/seclists")

SUBDOMAIN_WORDLIST = (
    SECLISTS / "Discovery/DNS/subdomains-top1million-20000.txt"
)

WEB_WORDLIST = (
    SECLISTS / "Discovery/Web-Content/raft-medium-directories.txt"
)

HOSTS_FILE = Path("/etc/hosts")

HTB_START = "###HTB"
HTB_END = "###END_HTB"

FFUF_MATCH_CODES = "200,204,301,302,307,401,403"
FFUF_THREADS = "30"

CURL_TIMEOUT = 10


def print_section(title):
    print()
    print("=" * 72)
    print(f"[+] {title}")
    print("=" * 72)


def run_command(command, output_file=None):
    print()
    print(f"[>] {' '.join(command)}")

    if output_file:
        print(f"[>] Output: {output_file}")

    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )

    except FileNotFoundError:
        print(
            f"[!] Command not found: {command[0]}"
        )
        return 127, ""

    except KeyboardInterrupt:
        print()
        print("[!] Interrupted by user.")
        return 130, ""

    if output_file:
        Path(output_file).write_text(
            result.stdout,
            encoding="utf-8",
        )

    return result.returncode, result.stdout


def parse_open_ports(nmap_output):
    ports = []

    for line in nmap_output.splitlines():
        match = re.match(
            r"^\s*(\d+)/tcp\s+open\s+",
            line,
        )

        if match:
            ports.append(
                match.group(1)
            )

    return sorted(
        set(ports),
        key=int,
    )


def parse_nmap_xml(xml_file):
    services = {}

    try:
        root = ET.parse(
            xml_file
        ).getroot()

    except (
        FileNotFoundError,
        ET.ParseError,
    ):
        return services

    for port in root.findall(
        ".//port"
    ):
        protocol = port.get(
            "protocol"
        )

        portid = port.get(
            "portid"
        )

        if (
            protocol != "tcp"
            or not portid
        ):
            continue

        state = port.find(
            "state"
        )

        if (
            state is None
            or state.get("state") != "open"
        ):
            continue

        service = port.find(
            "service"
        )

        if service is None:
            continue

        scripts = []

        for script in port.findall(
            "./script"
        ):
            script_id = script.get(
                "id"
            )

            output = script.get(
                "output"
            )

            if script_id:
                scripts.append(
                    {
                        "id": script_id,
                        "output": output or "",
                    }
                )

        services[portid] = {
            "name": service.get(
                "name",
                "",
            ),
            "product": service.get(
                "product",
                "",
            ),
            "version": service.get(
                "version",
                "",
            ),
            "extrainfo": service.get(
                "extrainfo",
                "",
            ),
            "tunnel": service.get(
                "tunnel",
                "",
            ),
            "scripts": scripts,
        }

    return services


def is_web_service(service):
    name = service.get(
        "name",
        "",
    ).lower()

    product = service.get(
        "product",
        "",
    ).lower()

    tunnel = service.get(
        "tunnel",
        "",
    ).lower()

    web_names = {
        "http",
        "https",
        "http-alt",
        "http-proxy",
    }

    if name in web_names:
        return True

    if name.startswith("http"):
        return True

    if "http" in name:
        return True

    if (
        tunnel == "ssl"
        and (
            "http" in name
            or "apache" in product
            or "nginx" in product
        )
    ):
        return True

    return False


def get_web_scheme(service):
    name = service.get(
        "name",
        "",
    ).lower()

    tunnel = service.get(
        "tunnel",
        "",
    ).lower()

    if (
        name == "https"
        or tunnel == "ssl"
    ):
        return "https"

    return "http"


def extract_hostname(url):
    if not url:
        return None

    try:
        parsed = urlparse(
            url
        )

        hostname = parsed.hostname

        if hostname:
            return hostname.lower()

    except Exception:
        pass

    return None


def get_origin(url):
    if not url:
        return None

    try:
        parsed = urlparse(
            url
        )

        if not parsed.scheme or not parsed.netloc:
            return None

        return (
            f"{parsed.scheme}://"
            f"{parsed.netloc}"
        )

    except Exception:
        return None


def is_ip_address(hostname):
    if not hostname:
        return False

    return bool(
        re.fullmatch(
            r"\d{1,3}(?:\.\d{1,3}){3}",
            hostname,
        )
    )


def is_redirect_probe(
    probe,
    original_url,
):
    """
    Returns True when the original web service redirects
    somewhere else.

    Example:
        http://10.10.10.10/
            ->
        https://management.htb/

    """

    initial_status = probe.get(
        "first_status"
    )

    effective_url = probe.get(
        "effective_url"
    )

    if (
        initial_status is None
        or effective_url is None
    ):
        return False

    if not (
        300 <= initial_status < 400
    ):
        return False

    normalized_original = (
        original_url.rstrip("/")
    )

    normalized_effective = (
        effective_url.rstrip("/")
    )

    return (
        normalized_original
        != normalized_effective
    )


def curl_probe(
    url,
    timeout=CURL_TIMEOUT,
):
    """
    Runs curl -kL and extracts:
    - first HTTP status
    - final HTTP status
    - final effective URL

    url_effective is parsed even when curl exits
    with a non-zero code because the final hostname
    may not exist in /etc/hosts yet.
    """

    if shutil.which("curl") is None:
        print(
            "[!] curl not found."
        )

        return {
            "returncode": 127,
            "first_status": None,
            "final_status": None,
            "effective_url": None,
            "output": "",
        }

    marker = "__HTB_CURL_FINAL__"

    command = [
        "curl",
        "-kL",
        "-sS",
        "--max-redirs",
        "10",
        "--connect-timeout",
        str(timeout),
        "--max-time",
        str(timeout),
        "-D",
        "-",
        "-o",
        "/dev/null",
        "-w",
        (
            f"\n{marker}"
            f"\t%{{http_code}}"
            f"\t%{{url_effective}}\n"
        ),
        url,
    ]

    print()
    print(
        f"[>] {' '.join(command)}"
    )

    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )

    except KeyboardInterrupt:
        print()
        print(
            "[!] Interrupted by user."
        )

        return {
            "returncode": 130,
            "first_status": None,
            "final_status": None,
            "effective_url": None,
            "output": "",
        }

    output = result.stdout

    marker_match = re.search(
        rf"{re.escape(marker)}\t(\d{{3}})\t([^\r\n]+)",
        output,
    )

    final_status = None
    effective_url = None

    if marker_match:
        final_status = int(
            marker_match.group(1)
        )

        effective_url = (
            marker_match.group(2)
            .strip()
        )

    header_data = output

    if marker_match:
        header_data = output[
            :marker_match.start()
        ]

    status_matches = re.findall(
        r"^HTTP/\S+\s+(\d{3})",
        header_data,
        re.MULTILINE,
    )

    first_status = (
        int(status_matches[0])
        if status_matches
        else final_status
    )

    if result.returncode != 0:
        print(
            f"[!] curl returned exit code "
            f"{result.returncode}"
        )

        if effective_url:
            print(
                f"[+] url_effective: "
                f"{effective_url}"
            )

    return {
        "returncode": result.returncode,
        "first_status": first_status,
        "final_status": final_status,
        "effective_url": effective_url,
        "output": output,
    }


def get_htb_section(lines):
    try:
        start = lines.index(
            HTB_START
        )

        end = lines.index(
            HTB_END,
            start + 1,
        )

        return (
            start,
            end,
        )

    except ValueError:
        return (
            None,
            None,
        )


def update_hosts_file(
    ip,
    hostnames,
):
    hostnames = sorted(
        {
            hostname.strip().lower()
            for hostname in hostnames
            if hostname.strip()
            and not is_ip_address(
                hostname.strip()
            )
        }
    )

    if not hostnames:
        return False

    try:
        content = HOSTS_FILE.read_text(
            encoding="utf-8"
        )

    except PermissionError:
        print(
            "[!] Cannot read /etc/hosts."
        )

        print(
            "[!] Run with sudo."
        )

        return False

    lines = content.splitlines()

    start, end = get_htb_section(
        lines
    )

    if start is None:
        print(
            "[!] Missing "
            "###HTB / ###END_HTB markers."
        )

        return False

    new_entry = (
        f"{ip}\t"
        f"{' '.join(hostnames)}"
    )

    new_lines = lines[
        :start + 1
    ]

    for line in lines[
        start + 1:end
    ]:
        stripped = line.strip()

        if not stripped:
            new_lines.append(
                line
            )
            continue

        if stripped.startswith("#"):
            new_lines.append(
                line
            )
            continue

        parts = stripped.split()

        if parts and parts[0] == ip:
            continue

        new_lines.append(
            "#" + line
        )

    new_lines.append(
        new_entry
    )

    new_lines.extend(
        lines[end:]
    )

    try:
        HOSTS_FILE.write_text(
            "\n".join(new_lines) + "\n",
            encoding="utf-8",
        )

    except PermissionError:
        print(
            "[!] Cannot write /etc/hosts."
        )

        print(
            "[!] Run with sudo."
        )

        return False

    print(
        "[+] /etc/hosts:"
    )

    print(
        f"    {new_entry}"
    )

    return True


def parse_ffuf_json(
    json_file,
):
    try:
        data = json.loads(
            Path(json_file).read_text(
                encoding="utf-8"
            )
        )

    except (
        FileNotFoundError,
        json.JSONDecodeError,
    ):
        return []

    return data.get(
        "results",
        []
    )


def parse_vhosts(
    json_file,
    base_domain,
):
    hosts = set()

    suffix = (
        f".{base_domain.lower()}"
    )

    for result in parse_ffuf_json(
        json_file
    ):
        host = result.get(
            "host"
        )

        if not host:
            continue

        host = host.strip().lower()

        if host.endswith(
            suffix
        ):
            hosts.add(
                host
            )

    return hosts


def print_vhost_results(
    json_file,
):
    results = parse_ffuf_json(
        json_file
    )

    if not results:
        print(
            "[-] No VHosts found."
        )

        return

    print(
        "[+] VHosts found:"
    )

    for result in results:

        host = result.get(
            "host",
            "?",
        )

        status = result.get(
            "status",
            "?",
        )

        size = result.get(
            "length",
            "?",
        )

        words = result.get(
            "words",
            "?",
        )

        print(
            f"    {host:<35}"
            f"[{status}] "
            f"Size:{size} "
            f"Words:{words}"
        )


def print_endpoint_results(
    json_file,
):
    results = parse_ffuf_json(
        json_file
    )

    if not results:
        print(
            "[-] No endpoints found."
        )

        return

    print(
        "[+] Endpoints found:"
    )

    for result in results:

        url = result.get(
            "url",
            "?",
        )

        status = result.get(
            "status",
            "?",
        )

        size = result.get(
            "length",
            "?",
        )

        words = result.get(
            "words",
            "?",
        )

        print(
            f"    [{status}] "
            f"{url} "
            f"(size:{size}, "
            f"words:{words})"
        )


def endpoint_results_for_summary(
    json_file,
):
    results = []

    for result in parse_ffuf_json(
        json_file
    ):
        url = result.get(
            "url"
        )

        if not url:
            continue

        parsed = urlparse(
            url
        )

        results.append(
            {
                "path": (
                    parsed.path
                    or "/"
                ),
                "status": result.get(
                    "status"
                ),
                "size": result.get(
                    "length"
                ),
                "words": result.get(
                    "words"
                ),
                "lines": result.get(
                    "lines"
                ),
            }
        )

    return results


def run_vhost_fuzzing(
    base_url,
    domain,
    output_dir,
):
    if not SUBDOMAIN_WORDLIST.exists():

        print(
            "[!] Missing VHost wordlist:"
        )

        print(
            f"    {SUBDOMAIN_WORDLIST}"
        )

        return set()

    json_file = (
        output_dir
        / "vhosts.json"
    )

    text_file = (
        output_dir
        / "vhosts.txt"
    )

    print(
        "[+] Starting VHost fuzzing..."
    )

    rc, _ = run_command(
        [
            "ffuf",
            "-s",
            "-t",
            FFUF_THREADS,
            "-w",
            str(
                SUBDOMAIN_WORDLIST
            ),
            "-u",
            f"{base_url}/",
            "-H",
            f"Host: FUZZ.{domain}",
            "-mc",
            FFUF_MATCH_CODES,
            "-ac",
            "-of",
            "json",
            "-o",
            str(
                json_file
            ),
        ],
        text_file,
    )

    if rc == 130:
        print(
            "[!] VHost fuzzing interrupted."
        )

        return set()

    print_vhost_results(
        json_file
    )

    return parse_vhosts(
        json_file,
        domain,
    )


def run_endpoint_fuzzing(
    scheme,
    port,
    hostname,
    output_dir,
):
    if not WEB_WORDLIST.exists():

        print(
            "[!] Missing endpoint wordlist:"
        )

        print(
            f"    {WEB_WORDLIST}"
        )

        return

    safe_hostname = re.sub(
        r"[^a-zA-Z0-9._-]",
        "_",
        hostname,
    )

    json_file = (
        output_dir
        / f"endpoints-{safe_hostname}.json"
    )

    text_file = (
        output_dir
        / f"endpoints-{safe_hostname}.txt"
    )

    target_url = (
        f"{scheme}://"
        f"{hostname}:"
        f"{port}"
    )

    print(
        f"[+] Endpoint fuzzing: "
        f"{hostname}"
    )

    rc, _ = run_command(
        [
            "ffuf",
            "-s",
            "-t",
            FFUF_THREADS,
            "-w",
            str(
                WEB_WORDLIST
            ),
            "-u",
            f"{target_url}/FUZZ",
            "-H",
            f"Host: {hostname}",
            "-mc",
            FFUF_MATCH_CODES,
            "-ac",
            "-of",
            "json",
            "-o",
            str(
                json_file
            ),
        ],
        text_file,
    )

    if rc == 130:
        print(
            "[!] Endpoint fuzzing interrupted."
        )

        return

    print_endpoint_results(
        json_file
    )


def main():
    parser = argparse.ArgumentParser(
        description=(
            "HTB reconnaissance wrapper"
        )
    )

    parser.add_argument(
        "ip",
        help="Target IPv4 address",
    )

    parser.add_argument(
        "output",
        nargs="?",
        default=".",
        help="Output directory",
    )

    args = parser.parse_args()

    ip = args.ip

    output_dir = (
        Path(args.output)
        .expanduser()
        .resolve()
    )

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    nmap_full = (
        output_dir
        / "nmap-full.txt"
    )

    nmap_services = (
        output_dir
        / "nmap-services.txt"
    )

    nmap_xml = (
        output_dir
        / "nmap-services.xml"
    )

    summary_file = (
        output_dir
        / "summary.json"
    )

    summary = {
        "target": ip,
        "ports": [],
        "hosts": [],
        "web": [],
    }

    # =========================================================
    # 1. Full TCP scan
    # =========================================================

    print_section(
        "1/4 - Full TCP scan"
    )

    rc, full_output = run_command(
        [
            "nmap",
            "-n",
            "-sS",
            "-p-",
            "--min-rate",
            "1000",
            "-T4",
            ip,
        ],
        nmap_full,
    )

    if rc == 130:
        return 130

    open_ports = parse_open_ports(
        full_output
    )

    if not open_ports:

        print(
            "[!] No open TCP ports found."
        )

        return 1

    print(
        "[+] Open ports:"
    )

    for port in open_ports:

        print(
            f"    - {port}"
        )

    # =========================================================
    # 2. Service detection
    # =========================================================

    print_section(
        "2/4 - Service and version detection"
    )

    rc, _ = run_command(
        [
            "nmap",
            "-n",
            "-sC",
            "-sV",
            "-p",
            ",".join(open_ports),
            "-oX",
            str(nmap_xml),
            ip,
        ],
        nmap_services,
    )

    if rc == 130:
        return 130

    services = parse_nmap_xml(
        nmap_xml
    )

    for port in sorted(
        services,
        key=int,
    ):

        service = services[
            port
        ]

        summary["ports"].append(
            {
                "port": int(port),
                "protocol": "tcp",
                "service": service.get(
                    "name"
                ) or "unknown",
                "product": service.get(
                    "product"
                ) or "",
                "version": service.get(
                    "version"
                ) or "",
                "extrainfo": service.get(
                    "extrainfo"
                ) or "",
            }
        )

        name = service.get(
            "name",
            "",
        )

        product = service.get(
            "product",
            "",
        )

        version = service.get(
            "version",
            "",
        )

        description = (
            f"{product} {version}"
        ).strip()

        if description:

            print(
                f"    {port}/tcp "
                f"{name:<12} "
                f"{description}"
            )

        else:

            print(
                f"    {port}/tcp "
                f"{name or 'unknown'}"
            )

    # =========================================================
    # 3. Detect all web services
    # =========================================================

    print_section(
        "3/4 - Web service discovery"
    )

    web_services = {}

    for port, service in services.items():

        if is_web_service(
            service
        ):
            web_services[
                port
            ] = service

    if not web_services:

        print(
            "[-] No web services detected."
        )

        summary_file.write_text(
            json.dumps(
                summary,
                indent=2,
            ),
            encoding="utf-8",
        )

        print(
            f"[+] Summary: "
            f"{summary_file}"
        )

        return 0

    print(
        "[+] Web services:"
    )

    for port in sorted(
        web_services,
        key=int,
    ):

        scheme = get_web_scheme(
            web_services[
                port
            ]
        )

        print(
            f"    - "
            f"{scheme}://"
            f"{ip}:{port}"
        )

    # =========================================================
    # 4. HTTP enumeration
    # =========================================================

    print_section(
        "4/4 - HTTP enumeration"
    )

    all_hosts = set()

    for port in sorted(
        web_services,
        key=int,
    ):

        service = web_services[
            port
        ]

        scheme = get_web_scheme(
            service
        )

        ip_base_url = (
            f"{scheme}://"
            f"{ip}:{port}"
        )

        port_dir = (
            output_dir
            / f"web-{port}"
        )

        port_dir.mkdir(
            parents=True,
            exist_ok=True,
        )

        web_summary = {
            "port": int(port),
            "scheme": scheme,
            "base": ip_base_url,
            "effective_url": None,
            "redirect": None,
            "hosts": [],
            "vhosts": [],
            "endpoints": {},
            "enumeration_skipped": False,
            "skip_reason": None,
        }

        print_section(
            f"Web target: "
            f"{ip_base_url}"
        )

        # -----------------------------------------------------
        # curl -kL
        # -----------------------------------------------------

        print(
            "[+] Resolving hostname with curl -kL..."
        )

        probe = curl_probe(
            f"{ip_base_url}/"
        )

        if probe[
            "returncode"
        ] == 130:
            return 130

        effective_url = probe[
            "effective_url"
        ]

        primary_hostname = extract_hostname(
            effective_url
        )

        redirect_file = (
            port_dir
            / "redirect.txt"
        )

        is_redirect = is_redirect_probe(
            probe,
            ip_base_url,
        )

        if effective_url:

            web_summary[
                "effective_url"
            ] = effective_url

            redirect_file.write_text(
                (
                    f"Initial URL: "
                    f"{ip_base_url}/\n"
                    f"Initial status: "
                    f"{probe['first_status']}\n"
                    f"Effective URL: "
                    f"{effective_url}\n"
                    f"Final status: "
                    f"{probe['final_status']}\n"
                ),
                encoding="utf-8",
            )

            print(
                f"[+] Initial HTTP status: "
                f"{probe['first_status']}"
            )

            print(
                f"[+] Effective URL: "
                f"{effective_url}"
            )

            if is_redirect:

                print(
                    f"[+] Redirect detected: "
                    f"{ip_base_url}/ -> "
                    f"{effective_url}"
                )

                web_summary[
                    "redirect"
                ] = effective_url

            if (
                primary_hostname
                and not is_ip_address(
                    primary_hostname
                )
            ):

                print(
                    f"[+] Hostname: "
                    f"{primary_hostname}"
                )

                web_summary[
                    "hosts"
                ].append(
                    primary_hostname
                )

                all_hosts.add(
                    primary_hostname
                )

                update_hosts_file(
                    ip,
                    all_hosts,
                )

        else:

            print(
                "[-] Could not determine "
                "effective URL."
            )

            redirect_file.write_text(
                "No effective URL found\n",
                encoding="utf-8",
            )

        # -----------------------------------------------------
        # If this service redirects, stop enumerating it.
        #
        # Typical:
        #   80 -> 443
        #
        # We already got the hostname from the redirect and
        # continue with the actual destination web service.
        # -----------------------------------------------------

        if is_redirect:

            web_summary[
                "enumeration_skipped"
            ] = True

            web_summary[
                "skip_reason"
            ] = (
                "Web service redirects "
                "to another URL"
            )

            print(
                "[-] Redirect detected."
            )

            print(
                "[-] Skipping VHost "
                "and endpoint enumeration."
            )

            summary[
                "web"
            ].append(
                web_summary
            )

            continue

        # -----------------------------------------------------
        # Non-redirecting service
        # -----------------------------------------------------

        if (
            primary_hostname
            and not is_ip_address(
                primary_hostname
            )
        ):

            print(
                "[+] Verifying hostname..."
            )

            hostname_url = (
                f"{scheme}://"
                f"{primary_hostname}:"
                f"{port}/"
            )

            verify = curl_probe(
                hostname_url
            )

            if verify[
                "effective_url"
            ]:

                print(
                    f"[+] Verified URL: "
                    f"{verify['effective_url']}"
                )

        # -----------------------------------------------------
        # VHost fuzzing
        # -----------------------------------------------------

        vhosts = set()

        if (
            primary_hostname
            and not is_ip_address(
                primary_hostname
            )
        ):

            vhost_base = (
                f"{scheme}://"
                f"{primary_hostname}:"
                f"{port}"
            )

            vhosts = run_vhost_fuzzing(
                vhost_base,
                primary_hostname,
                port_dir,
            )

            web_summary[
                "vhosts"
            ] = sorted(
                vhosts
            )

            all_hosts.update(
                vhosts
            )

            if vhosts:

                update_hosts_file(
                    ip,
                    all_hosts,
                )

        else:

            print(
                "[-] No domain available "
                "for VHost fuzzing."
            )

        # -----------------------------------------------------
        # Host list for endpoint fuzzing
        # -----------------------------------------------------

        web_hosts = set()

        if (
            primary_hostname
            and not is_ip_address(
                primary_hostname
            )
        ):

            web_hosts.add(
                primary_hostname
            )

        web_hosts.update(
            web_summary[
                "vhosts"
            ]
        )

        if web_hosts:

            all_hosts.update(
                web_hosts
            )

            update_hosts_file(
                ip,
                all_hosts,
            )

        # -----------------------------------------------------
        # Endpoint fuzzing
        # -----------------------------------------------------

        if web_hosts:

            for hostname in sorted(
                web_hosts
            ):

                run_endpoint_fuzzing(
                    scheme,
                    port,
                    hostname,
                    port_dir,
                )

                safe_hostname = re.sub(
                    r"[^a-zA-Z0-9._-]",
                    "_",
                    hostname,
                )

                endpoint_json = (
                    port_dir
                    / f"endpoints-"
                    f"{safe_hostname}.json"
                )

                web_summary[
                    "endpoints"
                ][hostname] = (
                    endpoint_results_for_summary(
                        endpoint_json
                    )
                )

        else:

            run_endpoint_fuzzing(
                scheme,
                port,
                ip,
                port_dir,
            )

            web_summary[
                "endpoints"
            ][ip] = (
                endpoint_results_for_summary(
                    port_dir
                    / "endpoints-"
                    f"{ip}.json"
                )
            )

        summary[
            "web"
        ].append(
            web_summary
        )

    # =========================================================
    # Final /etc/hosts update
    # =========================================================

    if all_hosts:

        print_section(
            "Final /etc/hosts update"
        )

        update_hosts_file(
            ip,
            all_hosts,
        )

    summary["hosts"] = sorted(
        all_hosts
    )

    # =========================================================
    # Save summary
    # =========================================================

    summary_file.write_text(
        json.dumps(
            summary,
            indent=2,
        ),
        encoding="utf-8",
    )

    # =========================================================
    # Final summary
    # =========================================================

    print_section(
        "RECON COMPLETE"
    )

    print(
        f"[+] Target: {ip}"
    )

    print(
        "[+] Open ports:"
    )

    for port in summary[
        "ports"
    ]:

        description = (
            f"{port['product']} "
            f"{port['version']}"
        ).strip()

        if description:

            print(
                f"    {port['port']}/tcp "
                f"{port['service']} "
                f"- {description}"
            )

        else:

            print(
                f"    {port['port']}/tcp "
                f"{port['service']}"
            )

    if summary["hosts"]:

        print()
        print(
            "[+] Hosts:"
        )

        for hostname in summary[
            "hosts"
        ]:

            print(
                f"    - {hostname}"
            )

    print()
    print(
        f"[+] Summary: "
        f"{summary_file}"
    )

    print(
        f"[+] Details: "
        f"{output_dir}"
    )

    return 0


if __name__ == "__main__":

    try:
        sys.exit(
            main()
        )

    except KeyboardInterrupt:

        print()
        print(
            "[!] Recon interrupted."
        )

        sys.exit(130)
