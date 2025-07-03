# Mint tokens to the user's address using the correct owner
$OWNER_PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
$TOKEN_ADDRESS = "0x22753E4264FDDc6181dc7cce468904A80a363E44"
$USER_ADDRESS = "0x2A946dD687381c39D1aCb16E9Dd6f91F98Ff33E8"
$AMOUNT = "10000000000000000000000"  # 10,000 tokens

cast send --private-key $OWNER_PRIVATE_KEY $TOKEN_ADDRESS --rpc-url http://localhost:8545 --gas-limit 100000 "mint(address,uint256)" $USER_ADDRESS $AMOUNT 