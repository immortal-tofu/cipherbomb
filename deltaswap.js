// const deltaSwap = (a, mask, delta) => {
//   const b = (a ^ (a >> delta)) & mask;
//   return a ^ b ^ (b << delta);
// };

// const reverseDeltaSwap = (a, mask, delta) => {
//   const b = (a ^ (a << delta)) & mask;
//   return a ^ b ^ (b >> delta);
// };

const MAX_ROUNDS = 9;

function rotateRight(n, d) {
  const bits = 8;
  return ((n >>> d % 8) | (n << (bits - (d % 8)))) & 255;
}

function rotateLeft(n, d) {
  const bits = 8;
  return ((n << d % bits) | (n >>> (bits - (d % bits)))) & 255;
}

const deltaSwap = (a, mask, delta) => {
  const b = rotateRight(a, delta) & mask;
  const c = rotateLeft(a, delta) & rotateRight(mask, delta);
  return b | c;
};

// const random = Math.floor(Math.random() * Number.MAX_SAFE_INTEGER);
const random = 124240025895334;
const original = 240;

const masks = [0x55, 0x33, 0x0f];
const deltas = [1, 2, 4];

console.log("original", original, original.toString(2));

const swapped = deltaSwap(original, masks[1], deltas[1]);
console.log("Swapped:", swapped.toString(2));

const restored = deltaSwap(swapped, masks[1], deltas[1]);
console.log("Restored:", restored, restored.toString(2));
const intermediate = [];
let val = original;
console.log("Encrypted");
let rand = random;
for (let i = 0; i < MAX_ROUNDS; i += 1) {
  const index = i % masks.length;

  console.log("-----------");
  rand = rotateRight(rand, 3);
  let mask = rotateRight(masks[index], rand & 0xff);
  console.log("Before enc:", i, index, "mask", mask, "val", val);
  val = deltaSwap(val, mask, deltas[index]);
  console.log("After enc:", i, index, val);
  if (intermediate.indexOf(val) < 0) intermediate.push(val);
}

console.log("--");
console.log("Encrypted", val);

console.log("-----------");

rand = rotateRight(random, 3 * (MAX_ROUNDS + 1));
for (let i = MAX_ROUNDS - 1; i >= 0; i -= 1) {
  const index = i % masks.length;
  console.log("-----------");
  rand = rotateLeft(rand, 3);
  let mask = rotateRight(masks[index], rand & 0xff);
  console.log("Before dec:", i, index, "mask", mask, "val", val);
  val = deltaSwap(val, mask, deltas[index]);
  console.log("After dec:", i, index, val);
}
console.log("--");

console.log("Decrypted", val);

console.log("intermediate", intermediate);
