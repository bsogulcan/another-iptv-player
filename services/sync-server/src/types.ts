export interface AuthContext {
  userId: number;
  username: string;
  deviceTokenId: number;
  deviceName: string;
}

declare global {
  namespace Express {
    interface Request {
      auth?: AuthContext;
    }
  }
}

export {};
