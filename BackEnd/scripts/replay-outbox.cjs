/* Operator-only replay of a recorded, dead-lettered event. No side effects beyond resetting its status. */
require('dotenv/config');
const {Pool}=require('pg');
const key=process.argv[2];
if(!key||key.length>180){console.error('Usage: node scripts/replay-outbox.cjs <event_key>');process.exit(2);}
const db=new Pool({connectionString:process.env.DATABASE_URL});
(async()=>{try{
 const result=await db.query(`UPDATE outbox_events SET status='PENDING',attempt_count=0,available_at=now(),published_at=NULL,last_error=NULL
 WHERE event_key=$1 AND status='DEAD_LETTER' AND NOT EXISTS
 (SELECT 1 FROM outbox_consumptions WHERE event_key=$1) RETURNING event_key`,[key]);
 if(!result.rowCount){console.error('No unacknowledged dead-letter event found.');process.exitCode=1;}
 else console.log(`Event ${result.rows[0].event_key} marked for replay; receiver must deduplicate event_key.`);
}finally{await db.end();}})().catch(e=>{console.error('Replay failed:',e.message);process.exitCode=1;});
