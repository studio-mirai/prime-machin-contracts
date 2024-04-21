import json
import subprocess
import re
from time import sleep
import urllib.request
from pathlib import Path
import os

PROJECT_ROOT = Path(__file__).parent.parent
NETWORK = os.environ["NETWORK"]

SM_API_ADDRESS = ""
SM_TREASURY_ADDRESS = "0xde0053243f3226649701a7fe2c3988be11941bf3ff3535f3c8c5bf32fc600220"  # fmt: skip


if NETWORK == "localnet":
    RPC_URL = "http://127.0.0.1:9000"
    GAS_URL = "http://127.0.0.1:9123/gas"
elif NETWORK == "mirainet":
    RPC_URL = "https://mirainet.fly.dev"
    GAS_URL = "https://mirainet.fly.dev/gas"
elif NETWORK == "testnet":
    RPC_URL = "http://185.8.106.111:9000"
elif NETWORK == "mainnet":
    RPC_URL = "http://5.199.172.142:9000"


def request_sui_from_faucet():
    headers = {"Content-Type": "application/json"}
    payload = {
        "FixedAmountRequest": {
            "recipient": "0x43888ff633a296d4d87026ee10a4d9f3ca649ea3403190a45ddd9712948d73cb"
        }
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(GAS_URL, data=data, headers=headers, method="POST")

    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read().decode())
        print(result)

    return


def get_publisher_module_name(
    object_id: str,
):
    print(f"Fetching object {object_id}...")

    headers = {"Content-Type": "application/json"}
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "sui_getObject",
        "params": [
            object_id,
            {
                "showType": False,
                "showOwner": False,
                "showPreviousTransaction": False,
                "showDisplay": False,
                "showContent": True,
                "showBcs": False,
                "showStorageRebate": False,
            },
        ],
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(RPC_URL, data=data, headers=headers, method="POST")

    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read().decode())

    print(result)

    return str(result["result"]["data"]["content"]["fields"]["module_name"]).title()


def transfer_object(
    object_id: str,
    to: str,
):
    cmd = f"sui client transfer --to {to} --object-id {object_id} --gas-budget 1000000000"  # fmt: skip
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
    output, error = process.communicate()
    print(output)
    return


def deploy():
    cmd = "sui client publish --gas-budget 1000000000 --json"

    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
    output, error = process.communicate()

    print(output)

    result = json.loads(output.decode("utf-8"))

    object_changes = result["objectChanges"]

    config = {}

    print(json.dumps(object_changes, indent=4))

    sleep(3)

    for change in object_changes:
        if change["type"] == "published":
            config["PackageId"] = change["packageId"]
        elif change["type"] == "created":
            if "Display" in change["objectType"]:
                display_type = re.findall(r".*::(.*)\>", change["objectType"])[0]
                config[f"{display_type}Display"] = change["objectId"]
            elif "TransferPolicyCap" in change["objectType"]:
                config["TransferPolicyCap"] = change["objectId"]
            elif "TransferPolicy" in change["objectType"]:
                config["TransferPolicy"] = change["objectId"]
            elif change["objectType"].startswith("0x2::coin::Coin<") and change["objectType"].endswith("koto::KOTO>"):  # fmt: skip
                config["KotoCoin"] = change["objectId"]
            elif "CoinMetadata" in change["objectType"]:
                config["KotoCoinMetadata"] = change["objectId"]
            elif "TreasuryCap" in change["objectType"]:
                config["TreasuryCap"] = change["objectId"]
            elif "Publisher" in change["objectType"]:
                config[f"{get_publisher_module_name(change['objectId'])}Publisher"] = change["objectId"]  # fmt: skip
            else:
                config[re.findall(r"0x.*::(.*)", change["objectType"])[0]] = change["objectId"]  # fmt: skip

    sorted_config = dict(sorted(config.items(), key=lambda item: item[0]))

    with open(f"/Users/brianli/Documents/GitHub/prime-machin-api/prime_machin_api/package/{NETWORK}.json", "w+") as f:  # fmt: skip
        json.dump(sorted_config, f, indent=4)

    print("Config saved.")
    print(json.dumps(sorted_config, indent=4))

    print(f"Transferring UpgradeCap {sorted_config['UpgradeCap']} to {SM_TREASURY_ADDRESS}...")  # fmt: skip
    transfer_object(sorted_config["UpgradeCap"], SM_TREASURY_ADDRESS)


if NETWORK in ["localnet", "mirainet"]:
    for _ in range(5):
        request_sui_from_faucet()

deploy()
