import requests, sys, codecs
from eth_abi import encode

API_URL = "https://li.quest/v1"

def get_quote(
    srcToken , 
    dstToken , 
    amount , 
    fromAddress
): 
    queryParams = {
        "fromChain": 1,
        "toChain": 1,
        "fromToken": srcToken,
        "toToken": dstToken,
        "fromAmount": amount,
        "fromAddress": fromAddress,
        "integrator": 'stakedao'
    }

    url = API_URL + "/quote"
    resp = requests.get(url, params=queryParams).json()

    data = encode(
        ["uint256", "bytes"], [int(resp["estimate"]["toAmount"]), codecs.decode(resp['transactionRequest']['data'][2:], 'hex_codec')]
    ).hex()
    print("0x" +str(data))



def main():
    args = sys.argv[1:]
    return get_quote(*args)


__name__ == "__main__" and main()
