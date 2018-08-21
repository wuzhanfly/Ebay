pragma solidity ^0.4.24;
import "contracts/Escrow.sol";
contract EcommerceStore {
 enum ProductStatus { Open, Sold, Unsold }//产品状态
 enum ProductCondition { New, Used }

 uint public productIndex;//产品id
 mapping (address => mapping(uint => Product)) stores;
 mapping (uint => address) productIdInStore;//产品id,以及发布人add
 mapping (uint => address) productEscrow;

 struct Product {
  uint id;
  string name;//产品名字
  string category;//分类
  string imageLink;//图片hash
  string descLink;//图片描述哈希
  uint auctionStartTime;//开始竞标时间
  uint auctionEndTime;//结束时间
  uint startPrice;//价格
  address highestBidder;//竞标赢家钱包地址
  uint highestBid;//赢家竞标价格
  uint secondHighestBid;//第二高价格地址
  uint totalBids;//竞标人数
  ProductStatus status;//状态
  ProductCondition condition;//新，旧
  mapping (address => mapping (bytes32 => Bid)) bids;//竞标地址=》bytes32他投标信息（hash）
 }
 struct Bid {//投标信息
  address bidder;//投标人地址
  uint productId;
  uint value;//虚值
  bool revealed;//是否公告
  }
    constructor () public {
  productIndex = 0;
 }
 function numberOfItems() public view returns (uint) {
  return productIndex;
 }
 event bidCast(address bidder, uint productId, uint value);
 function bid2() public pure returns (bool) {
  // bidCast(msg.sender, 1, 2);
  return true;
 }
  event NewProduct(uint _productId, string _name, string _category, string _imageLink, string _descLink,
  uint _auctionStartTime, uint _auctionEndTime, uint _startPrice, uint _productCondition);

    /*投标*/
function bid(uint _productId, bytes32 _bid) public payable returns (bool) {
  Product storage product = stores[productIdInStore[_productId]][_productId];
  require (now >= product.auctionStartTime);
  require (now <= product.auctionEndTime);
  require (msg.value > product.startPrice);
  require (product.bids[msg.sender][_bid].bidder == 0);
  emit bidCast(msg.sender, _productId, msg.value);
  product.bids[msg.sender][_bid] = Bid(msg.sender, _productId, msg.value, false);
  product.totalBids += 1;
  return true;
}
    /*截标*/
function revealBid(uint _productId, string _amount, string _secret) public {
  Product storage product = stores[productIdInStore[_productId]][_productId];
  require (now > product.auctionEndTime);
  bytes32 sealedBid =  keccak256(abi.encodePacked(_amount,_secret));

  Bid memory bidInfo = product.bids[msg.sender][sealedBid];
  require (bidInfo.bidder > 0);
  require (bidInfo.revealed == false);

  uint refund;//退款

  uint amount = stringToUint(_amount);

  if(bidInfo.value < amount) {
   // They didn't send enough amount, they lost
   refund = bidInfo.value;
  } else {
   // If first to reveal set as highest bidder
   if (address(product.highestBidder) == 0) {
    product.highestBidder = msg.sender;
    product.highestBid = amount;
    product.secondHighestBid = product.startPrice;
    refund = bidInfo.value - amount;
   } else {
    if (amount > product.highestBid) {
     product.secondHighestBid = product.highestBid;
     product.highestBidder = msg.sender;
     product.highestBid = amount;
     refund = bidInfo.value - amount;
    } else if (amount > product.secondHighestBid) {
     product.secondHighestBid = amount;
     refund = amount;
    } else {
     refund = amount;
    }
   }
   if (refund > 0) {
    msg.sender.transfer(refund);
    product.bids[msg.sender][sealedBid].revealed = true;
   }
  }


}function highestBidderInfo(uint _productId) public view returns (address, uint, uint) {
  Product memory product = stores[productIdInStore[_productId]][_productId];
  return (product.highestBidder, product.highestBid, product.secondHighestBid);
}


/*竞标人数*/
function totalBids(uint _productId) public view returns (uint) {
  Product memory product = stores[productIdInStore[_productId]][_productId];
  return product.totalBids;
}



function stringToUint(string s) public pure  returns (uint) {
  bytes memory b = bytes(s);
  uint result = 0;
  for (uint i = 0; i < b.length; i++) {
    if (b[i] >= 48 && b[i] <= 57) {
      result = result * 10 + (uint(b[i]) - 48);
    }
  }
  return result;
}
    /*添加产品到区块链*/
 function addProductToStore(string _name, string _category, string _imageLink, string _descLink, uint _auctionStartTime, uint _auctionEndTime, uint _startPrice, uint _productCondition)public  {
  require(_auctionStartTime < _auctionEndTime);
  productIndex += 1;
  Product memory product = Product(productIndex, _name, _category, _imageLink, _descLink, _auctionStartTime, _auctionEndTime, _startPrice, 0, 0, 0, 0, ProductStatus.Open, ProductCondition(_productCondition));
  stores[msg.sender][productIndex] = product;
  productIdInStore[productIndex] = msg.sender;
  emit NewProduct(productIndex, _name, _category, _imageLink, _descLink, _auctionStartTime, _auctionEndTime, _startPrice, _productCondition);
 }
    /*通过产品id读取产品信息*/
 function getProduct(uint _productId) public view returns (uint, string, string, string, string, uint, uint, uint, ProductStatus, ProductCondition) {
  Product memory product = stores[productIdInStore[_productId]][_productId];
  return (product.id, product.name, product.category, product.imageLink, product.descLink, product.auctionStartTime,
      product.auctionEndTime, product.startPrice, product.status, product.condition);
  }

  function finalizeAuction(uint _productId)public {
  Product memory product = stores[productIdInStore[_productId]][_productId];
  // 48 hours to reveal the bid
  require(now > product.auctionEndTime);
  require(product.status == ProductStatus.Open);
  require(product.highestBidder != msg.sender);
  require(productIdInStore[_productId] != msg.sender);

  if (product.totalBids == 0) {
   product.status = ProductStatus.Unsold;
  } else {
   // Whoever finalizes the auction is the arbiter
   Escrow escrow = (new Escrow).value(product.secondHighestBid)(_productId, product.highestBidder, productIdInStore[_productId], msg.sender);
   productEscrow[_productId] = address(escrow);
   product.status = ProductStatus.Sold;
   // The bidder only pays the amount equivalent to second highest bidder
   // Refund the difference
   uint refund = product.highestBid - product.secondHighestBid;
   product.highestBidder.transfer(refund);

  }
 }
  function escrowAddressForProduct(uint _productId) public view returns (address) {
  return productEscrow[_productId];
 }

 function escrowInfo(uint _productId) public view returns (address, address, address, bool, uint, uint) {
  return Escrow(productEscrow[_productId]).escrowInfo();
}

function releaseAmountToSeller(uint _productId)public {
  Escrow(productEscrow[_productId]).releaseAmountToSeller(msg.sender);
}

function refundAmountToBuyer(uint _productId)public {
  Escrow(productEscrow[_productId]).refundAmountToBuyer(msg.sender);
}


}
