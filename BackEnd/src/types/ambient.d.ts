declare module 'express' {
  export type NextFunction = (error?: unknown) => void;
  export interface Request { method: string; path: string; originalUrl: string; headers: Record<string, any>; body: any; params: Record<string,string>; query: Record<string, any>; ip?: string; socket?: {remoteAddress?:string}; get(name:string): string | undefined; account?: any; session?: any; permissions?: Set<string>; }
  export interface Response { locals: Record<string,any>; setHeader(name:string,value:string): void; status(code:number): Response; json(body:any): Response; send(body?:any): Response; end(): Response; cookie(name:string,value:string,options?:any): Response; clearCookie(name:string,options?:any): Response; }
  export interface Router { use(...args:any[]): any; get(path:string,...handlers:any[]): any; post(path:string,...handlers:any[]): any; put(path:string,...handlers:any[]): any; patch(path:string,...handlers:any[]): any; delete(path:string,...handlers:any[]): any; }
  export type RequestHandler = (req: Request, res: Response, next: NextFunction) => any;
  interface ExpressFactory { (): any; json(options?:any): any; Router(): Router; }
  const express: ExpressFactory;
  export default express;
}
declare module 'node:crypto' { export const randomUUID:any, randomBytes:any, createHash:any, createHmac:any, timingSafeEqual:any, scrypt:any, createCipheriv:any, createDecipheriv:any; }
declare var process: any;
declare var Buffer: any;
declare var require: any;
declare var __dirname: string;
declare function fetch(input:any, init?:any): Promise<any>;
