import type {Service} from '../../types/Service'
export function servicePhoto(service: Pick<Service,'name'|'category_code'>) {
 const text=(service.name+' '+service.category_code).toLowerCase()
 return '/photos/'+(/boarding|hotel|penitipan/.test(text)?'boarding':/dog|anjing/.test(text)?'dog':'cat')+'.webp'
}
export function categoryLabel(code:string){return ({GROOMING:'Grooming',BOARDING:'Penitipan',PET_BOARDING:'Penitipan',VETERINARY:'Kesehatan',TRAINING:'Pelatihan',PET_SITTING:'Pet sitting',WALKING:'Jalan-jalan'} as Record<string,string>)[code]??code.replaceAll('_',' ').toLowerCase().replace(/^./,c=>c.toUpperCase())}
