export const COINS_PER_RUN = 30;
export const upgradeCost = (level: number) => level >= 3 ? null : (level + 1) * 25;
export const movement = (speed: number, jump: number) => ({ speed: 230 + speed * 35, jump: 430 + jump * 30 });
export const coinPosition = (id: number) => ({ x: 140 + Math.floor(id / 3) * 300 + (id % 3) * 60, y: 370 - (Math.floor(id / 3) % 3) * 28 });