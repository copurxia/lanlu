#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
/* in-memory + file-persisted KV with 2-byte column-family id prefix */
typedef struct { unsigned char* k; unsigned kl; unsigned char* v; unsigned vl; } KV;
static KV* g_kv=NULL; static int g_n=0,g_cap=0; static char g_path[1024];
static void save(void){ if(!g_path[0])return; FILE*f=fopen(g_path,"wb"); if(!f)return; fwrite(&g_n,4,1,f); for(int i=0;i<g_n;i++){ fwrite(&g_kv[i].kl,4,1,f); fwrite(g_kv[i].k,1,g_kv[i].kl,f); fwrite(&g_kv[i].vl,4,1,f); fwrite(g_kv[i].v,1,g_kv[i].vl,f);} fclose(f);} 
static void load(void){ g_n=0; FILE*f=fopen(g_path,"rb"); if(!f)return; int n=0; if(fread(&n,4,1,f)!=1){fclose(f);return;} for(int i=0;i<n;i++){ unsigned kl,vl; if(fread(&kl,4,1,f)!=1)break; unsigned char*k=malloc(kl?kl:1); if(fread(k,1,kl,f)!=kl){free(k);break;} if(fread(&vl,4,1,f)!=1){free(k);break;} unsigned char*v=malloc(vl?vl:1); if(fread(v,1,vl,f)!=vl){free(k);free(v);break;} if(g_n>=g_cap){g_cap=g_cap?g_cap*2:16; g_kv=realloc(g_kv,g_cap*sizeof(KV));} g_kv[g_n].k=k;g_kv[g_n].kl=kl;g_kv[g_n].v=v;g_kv[g_n].vl=vl;g_n++; } fclose(f);} 
static unsigned fnv(const char*s){ unsigned h=2166136261u; for(;*s;s++){h^=(unsigned char)*s;h*=16777619u;} unsigned id=h&0x7fffu; return id?id:1u; }
static void* mkhandle(unsigned id){ return (void*)(uintptr_t)(0x100000u + id); }
static unsigned dechandle(void* h){ uintptr_t p=(uintptr_t)h; if(p<0x100000u) return 0; return (unsigned)(p-0x100000u); }
/* effective key: 2-byte id (LE) + key */
static unsigned char* ek(unsigned id,const unsigned char*k,unsigned kl,unsigned* olen){ unsigned char* p=malloc(kl+2); p[0]=id&0xff; p[1]=(id>>8)&0xff; memcpy(p+2,k,kl); *olen=kl+2; return p; }
static int find(unsigned id,const unsigned char*k,unsigned kl){ for(int i=0;i<g_n;i++){ if(g_kv[i].kl!=kl+2) continue; if(g_kv[i].k[0]!=(id&0xff)||g_kv[i].k[1]!=((id>>8)&0xff)) continue; if(memcmp(g_kv[i].k+2,k,kl)==0) return i; } return -1; }
static void setkv(unsigned id,const unsigned char*k,unsigned kl,const unsigned char*v,unsigned vl){ int i=find(id,k,kl); if(i<0){ if(g_n>=g_cap){g_cap=g_cap?g_cap*2:16; g_kv=realloc(g_kv,g_cap*sizeof(KV));} i=g_n++; unsigned el; unsigned char* kk=ek(id,k,kl,&el); g_kv[i].k=kk; g_kv[i].kl=el; } else free(g_kv[i].v); g_kv[i].v=malloc(vl?vl:1); g_kv[i].vl=vl; memcpy(g_kv[i].v,v,vl); save(); }
static void delkv(unsigned id,const unsigned char*k,unsigned kl){ int i=find(id,k,kl); if(i<0)return; free(g_kv[i].k); free(g_kv[i].v); g_kv[i]=g_kv[g_n-1]; g_n--; save(); }
void* rocksdb_open_column_families(void* o,const char* n,int num,void* names,void* cfopts,void* handles,void* err){ (void)o;(void)cfopts; if(err)*(void**)err=0; snprintf(g_path,sizeof g_path,"%s/lanlu_kv.bin",n); load(); char** nm=(char**)names; void** h=(void**)handles; if(h) for(int i=0;i<num;i++) h[i]=mkhandle(nm&&nm[i]?fnv(nm[i]):1u); return (void*)1; }
void* rocksdb_create_column_family(void* db,void* o,const char* n,void* err){ (void)db;(void)o; if(err)*(void**)err=0; return mkhandle(n&&*n?fnv(n):1u); }
void rocksdb_drop_column_family(void* db,void* h,void* err){ (void)db;(void)h; if(err)*(void**)err=0; }
void rocksdb_column_family_handle_destroy(void* h){ (void)h; }
unsigned char* rocksdb_get(void* db,void* o,const char* k,unsigned kl,unsigned* vallen,void* err){ (void)db;(void)o; if(err)*(void**)err=0; int i=find(0,(const unsigned char*)k,kl); if(i<0){ if(vallen)*vallen=0; return 0;} unsigned char*r=malloc(g_kv[i].vl?g_kv[i].vl:1); memcpy(r,g_kv[i].v,g_kv[i].vl); if(vallen)*vallen=g_kv[i].vl; return r; }
unsigned char* rocksdb_get_cf(void* db,void* o,void* cf,const char* k,unsigned kl,unsigned* vallen,void* err){ (void)db;(void)o; unsigned id=dechandle(cf); if(err)*(void**)err=0; int i=find(id,(const unsigned char*)k,kl); if(i<0){ if(vallen)*vallen=0; return 0;} unsigned char*r=malloc(g_kv[i].vl?g_kv[i].vl:1); memcpy(r,g_kv[i].v,g_kv[i].vl); if(vallen)*vallen=g_kv[i].vl; return r; }
void rocksdb_put(void* db,void* o,const char* k,unsigned kl,const char* v,unsigned vl,void* err){ (void)db;(void)o; if(err)*(void**)err=0; setkv(0,(const unsigned char*)k,kl,(const unsigned char*)v,vl); }
void rocksdb_put_cf(void* db,void* o,void* cf,const char* k,unsigned kl,const char* v,unsigned vl,void* err){ (void)db;(void)o; if(err)*(void**)err=0; setkv(dechandle(cf),(const unsigned char*)k,kl,(const unsigned char*)v,vl); }
void rocksdb_merge(void* db,void* o,const char* k,unsigned kl,const char* v,unsigned vl,void* err){ rocksdb_put(db,o,k,kl,v,vl,err);} 
void rocksdb_merge_cf(void* db,void* o,void* cf,const char* k,unsigned kl,const char* v,unsigned vl,void* err){ rocksdb_put_cf(db,o,cf,k,kl,v,vl,err);} 
void rocksdb_delete(void* db,void* o,const char* k,unsigned kl,void* err){ (void)db;(void)o; if(err)*(void**)err=0; delkv(0,(const unsigned char*)k,kl);} 
void rocksdb_delete_cf(void* db,void* o,void* cf,const char* k,unsigned kl,void* err){ (void)db;(void)o; if(err)*(void**)err=0; delkv(dechandle(cf),(const unsigned char*)k,kl);} 
typedef struct BOP { int op; unsigned id; unsigned char*k; unsigned kl; unsigned char*v; unsigned vl; } BOP;
typedef struct { BOP* a; int n,c; } BATCH;
void* rocksdb_writebatch_create(){ return calloc(1,sizeof(BATCH)); }
void rocksdb_writebatch_destroy(void* p){ BATCH* b=p; if(!b)return; for(int i=0;i<b->n;i++){free(b->a[i].k); free(b->a[i].v);} free(b->a); free(b);} 
static void badd(void* p,int op,unsigned id,const char*k,unsigned kl,const char*v,unsigned vl){ BATCH* b=p; if(!b)return; if(b->n>=b->c){b->c=b->c?b->c*2:8; b->a=realloc(b->a,b->c*sizeof(BOP));} BOP*e=&b->a[b->n++]; e->op=op; e->id=id; e->kl=kl; e->k=malloc(kl?kl:1); memcpy(e->k,k,kl); e->vl=vl; e->v=malloc(vl?vl:1); if(v)memcpy(e->v,v,vl);} 
void rocksdb_writebatch_put(void* p,const char*k,unsigned kl,const char*v,unsigned vl){ badd(p,1,0,k,kl,v,vl);} 
void rocksdb_writebatch_put_cf(void* p,void* cf,const char*k,unsigned kl,const char*v,unsigned vl){ badd(p,1,dechandle(cf),k,kl,v,vl);} 
void rocksdb_writebatch_merge(void* p,const char*k,unsigned kl,const char*v,unsigned vl){ badd(p,1,0,k,kl,v,vl);} 
void rocksdb_writebatch_delete(void* p,const char*k,unsigned kl){ badd(p,0,0,k,kl,0,0);} 
void rocksdb_writebatch_delete_cf(void* p,void* cf,const char*k,unsigned kl){ badd(p,0,dechandle(cf),k,kl,0,0);} 
void rocksdb_writebatch_clear(void* p){ BATCH* b=p; if(!b)return; for(int i=0;i<b->n;i++){free(b->a[i].k);free(b->a[i].v);} b->n=0;} 
void rocksdb_write(void* db,void* o,void* p,void* err){ (void)db;(void)o; if(err)*(void**)err=0; BATCH* b=p; if(!b)return; for(int i=0;i<b->n;i++){ if(b->a[i].op==0) delkv(b->a[i].id,b->a[i].k,b->a[i].kl); else setkv(b->a[i].id,b->a[i].k,b->a[i].kl,b->a[i].v,b->a[i].vl);} }
/* ---- iterator, per column family ---- */
typedef struct { int* idx; int n; int pos; unsigned id; } ITER;
static int cmp_idx(const void*a,const void*b){int i=*(const int*)a,j=*(const int*)b; KV*x=&g_kv[i],*y=&g_kv[j]; unsigned xl=x->kl-2, yl=y->kl-2; unsigned m=xl<yl?xl:yl; int c=memcmp(x->k+2,y->k+2,m); if(c)return c; return (int)xl-(int)yl;}
static int keycmpi(int i,unsigned id,const unsigned char*k,unsigned kl){ KV*e=&g_kv[i]; (void)id; unsigned el=e->kl-2; unsigned m=el<kl?el:kl; int c=memcmp(e->k+2,k,m); if(c)return c; return (int)el-(int)kl;}
static ITER* mkit(unsigned id){ ITER*t=malloc(sizeof(ITER)); t->pos=0; t->id=id; int cap=16,n=0; int* arr=malloc(sizeof(int)*cap); for(int i=0;i<g_n;i++){ if(g_kv[i].kl<2) continue; if(g_kv[i].k[0]!=(id&0xff)||g_kv[i].k[1]!=((id>>8)&0xff)) continue; if(n>=cap){cap*=2;arr=realloc(arr,sizeof(int)*cap);} arr[n++]=i; } t->n=n; t->idx=arr; if(n>1) qsort(arr,n,sizeof(int),cmp_idx); return t; }
void* rocksdb_create_iterator_cf(void* db,void* o,void* cf){ (void)db;(void)o; return mkit(dechandle(cf)); }
void* rocksdb_create_iterator(void* db,void* o){ (void)db;(void)o; return mkit(0); }
unsigned char rocksdb_iter_valid(void* it){ ITER*t=it; return (t&&t->pos>=0&&t->pos<t->n)?1:0; }
void rocksdb_iter_seek_to_first(void* it){ ITER*t=it; if(t)t->pos=0; }
void rocksdb_iter_seek_to_last(void* it){ ITER*t=it; if(t)t->pos=t->n-1; }
void rocksdb_iter_seek(void* it,const char*k,unsigned kl){ ITER*t=it; if(!t)return; int lo=0,hi=t->n; while(lo<hi){int mid=(lo+hi)/2; if(keycmpi(t->idx[mid],t->id,(const unsigned char*)k,kl)<0) lo=mid+1; else hi=mid;} t->pos=lo; }
void rocksdb_iter_seek_for_prev(void* it,const char*k,unsigned kl){ ITER*t=it; if(!t)return; int lo=0,hi=t->n; while(lo<hi){int mid=(lo+hi)/2; if(keycmpi(t->idx[mid],t->id,(const unsigned char*)k,kl)<=0) lo=mid+1; else hi=mid;} t->pos=lo-1; }
void rocksdb_iter_next(void* it){ ITER*t=it; if(t)t->pos++; }
void rocksdb_iter_prev(void* it){ ITER*t=it; if(t)t->pos--; }
unsigned char* rocksdb_iter_key(void* it,unsigned* l){ ITER*t=it; if(!t||t->pos<0||t->pos>=t->n){ if(l)*l=0; return 0;} KV*e=&g_kv[t->idx[t->pos]]; if(l)*l=e->kl-2; return e->k+2; }
unsigned char* rocksdb_iter_value(void* it,unsigned* l){ ITER*t=it; if(!t||t->pos<0||t->pos>=t->n){ if(l)*l=0; return 0;} KV*e=&g_kv[t->idx[t->pos]]; if(l)*l=e->vl; return e->v; }
void rocksdb_iter_get_error(void* it,void* err){(void)it; if(err)*(void**)err=0;} void rocksdb_iter_destroy(void* it){ ITER*t=it; if(t){free(t->idx); free(t);} }
void rocksdb_flush(void* db,void* o,void* err){(void)db;(void)o; if(err)*(void**)err=0; save();}
void rocksdb_flush_cf(void* db,void* o,void* cf,void* err){(void)cf; rocksdb_flush(db,o,err);}
void rocksdb_close(void* db){(void)db; save();}
void rocksdb_free(void* p){ free(p);} 
unsigned long rocksdb_get_latest_sequence_number(void* db){(void)db; return 0;}
int rocksdb_property_int(void* db,const char*n,unsigned long*v){(void)db;(void)n; if(v)*v=0; return 0;}
unsigned char* rocksdb_property_value(void* db,const char*n){(void)db;(void)n; return 0;}
int rocksdb_property_int_cf(void* db,void*cf,const char*n,unsigned long*v){(void)db;(void)cf;(void)n; if(v)*v=0; return 0;}
unsigned char* rocksdb_property_value_cf(void* db,void*cf,const char*n){(void)db;(void)cf;(void)n; return 0;}
void rocksdb_approximate_sizes(void*db,int c,void*s,void*sl,void*e,void*el,void*sz,void*err){(void)db;(void)c;(void)s;(void)sl;(void)e;(void)el;(void)sz; if(err)*(void**)err=0;}
void rocksdb_approximate_sizes_cf(void*db,void*cf,int c,void*s,void*sl,void*e,void*el,void*sz,void*err){(void)db;(void)cf;(void)c;(void)s;(void)sl;(void)e;(void)el;(void)sz; if(err)*(void**)err=0;}

/* ---- generic stubs for unused rocksdb symbols ---- */
void* rocksdb_options_create(){ return (void*)1; }
void rocksdb_options_destroy(){}
void rocksdb_options_set_create_if_missing(){}
void rocksdb_options_set_paranoid_checks(){}
void rocksdb_options_set_write_buffer_size(){}
void rocksdb_options_set_db_write_buffer_size(){}
void rocksdb_options_set_max_open_files(){}
void rocksdb_options_set_max_write_buffer_number(){}
void rocksdb_options_set_min_write_buffer_number_to_merge(){}
void rocksdb_options_set_max_background_jobs(){}
void rocksdb_options_set_keep_log_file_num(){}
void rocksdb_options_set_use_fsync(){}
void rocksdb_options_set_allow_mmap_reads(){}
void rocksdb_options_set_bytes_per_sync(){}
void rocksdb_options_set_compression(){}
void* rocksdb_block_based_options_create(){ return (void*)1; }
void rocksdb_block_based_options_destroy(){}
void rocksdb_block_based_options_set_no_block_cache(){}
void rocksdb_block_based_options_set_block_cache(){}
void rocksdb_block_based_options_set_cache_index_and_filter_blocks(){}
void rocksdb_block_based_options_set_cache_index_and_filter_blocks_with_high_priority(){}
void rocksdb_block_based_options_set_pin_l0_filter_and_index_blocks_in_cache(){}
void rocksdb_block_based_options_set_pin_top_level_index_and_filter(){}
void rocksdb_options_set_block_based_table_factory(){}
void* rocksdb_cache_create_lru(){ return (void*)1; }
void rocksdb_cache_destroy(){}
void* rocksdb_open(){ return (void*)1; }
void* rocksdb_list_column_families(){ return 0; }
void rocksdb_list_column_families_destroy(){}
void* rocksdb_optimistictransactiondb_open(){ return (void*)1; }
void* rocksdb_optimistictransactiondb_get_base_db(){ return 0; }
void rocksdb_optimistictransactiondb_close_base_db(){}
void rocksdb_optimistictransactiondb_close(){}
void* rocksdb_readoptions_create(){ return (void*)1; }
void rocksdb_readoptions_destroy(){}
void rocksdb_readoptions_set_iterate_upper_bound(){}
void rocksdb_readoptions_set_prefix_same_as_start(){}
void rocksdb_readoptions_set_total_order_seek(){}
void rocksdb_readoptions_set_snapshot(){}
void rocksdb_readoptions_set_verify_checksums(){}
void rocksdb_readoptions_set_fill_cache(){}
void* rocksdb_writeoptions_create(){ return (void*)1; }
void rocksdb_writeoptions_destroy(){}
void rocksdb_writeoptions_set_sync(){}
void* rocksdb_transaction_options_create(){ return (void*)1; }
void rocksdb_transaction_options_destroy(){}
void rocksdb_transaction_options_set_set_snapshot(){}
void* rocksdb_optimistictransaction_options_create(){ return (void*)1; }
void rocksdb_optimistictransaction_options_destroy(){}
void rocksdb_optimistictransaction_options_set_set_snapshot(){}
void* rocksdb_optimistictransaction_begin(){ return (void*)1; }
void rocksdb_transaction_destroy(){}
long llrocksdb_compiled_major(){ return 0; }
long llrocksdb_compiled_minor(){ return 0; }
void rocksdb_transaction_commit(){}
void rocksdb_transaction_rollback(){}
void* rocksdb_transaction_get(){ return 0; }
void* rocksdb_transaction_get_cf(){ return 0; }
void rocksdb_transaction_multi_get(){}
void rocksdb_transaction_put(){}
void rocksdb_transaction_put_cf(){}
void rocksdb_transaction_delete_cf(){}
void rocksdb_transaction_delete(){}
void* rocksdb_create_snapshot(){ return (void*)1; }
void rocksdb_release_snapshot(){}
long llrocksdb_snapshot_get_sequence_number(){ return 0; }
void rocksdb_multi_get(){}
void rocksdb_writebatch_delete_range(){}
void rocksdb_writebatch_delete_range_cf(){}
void* rocksdb_flushoptions_create(){ return (void*)1; }
void rocksdb_flushoptions_destroy(){}
void rocksdb_flushoptions_set_wait(){}
void rocksdb_compact_range(){}
void rocksdb_compact_range_cf(){}
