# Call Graph Notes

deposit()
-> _mintShares()
-> updateRewards()

borrow()
-> validateCollateral()
-> oracle.getPrice()

liquidate()
-> healthCheck()
-> seizeCollateral()

