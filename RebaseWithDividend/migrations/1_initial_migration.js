const Token = artifacts.require("Titano");
const Router = artifacts.require("IDEXRouter");
const currTime = Number(Math.round(new Date().getTime() / 1000));

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(Token);

  let tokenInstance = await Token.deployed();

  await addLiq(tokenInstance, accounts[0]);


};

const addLiq = async (tokenInstance, account) => {

  const routerInstance = await Router.at(
    "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3"
  );
  
  let supply = await tokenInstance.totalSupply();
  await tokenInstance.approve(routerInstance.address, BigInt(supply), {
    from: account,
  });

  await routerInstance.addLiquidityETH(
    tokenInstance.address,
    BigInt(supply / 2),
    0,
    0,
    routerInstance.address,
    currTime + 100,
    { value: 1e17, from: account }
  );

}
