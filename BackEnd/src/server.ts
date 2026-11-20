import 'dotenv/config';
import { createApp } from './app';
import { env } from './config/env';
import { closeDatabase } from './shared/db/database';
const app=createApp();
const server=app.listen(env.port,()=>console.log(`PawPals API listening on port ${env.port} (${env.nodeEnv})`));
let shutting=false;
function shutdown(signal:string):void{if(shutting)return;shutting=true;console.log(`${signal} received. Shutting down PawPals API...`);server.close(async(error:any)=>{try{await closeDatabase();}finally{if(error){console.error('Failed to close HTTP server cleanly.',error);process.exitCode=1;}else process.exitCode=0;}});}
process.on('SIGTERM',()=>shutdown('SIGTERM'));process.on('SIGINT',()=>shutdown('SIGINT'));
