#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/time.h>
#include <math.h>
#include <time.h>
#include <upc.h>
#include <upc_io.h>

#include "upc_packingDNAseq.h"
#include "upc_kmer_hash.h"

//upc_lock_t heap_lock;
int main(int argc, char *argv[]){

	//heap_lock = upc_all_lock_alloc();
	/** Declarations **/
	double inputTime=0.0, constrTime=0.0, traversalTime=0.0;

	int64_t nKmers, avg_nKmers, rem_nKmers, my_lines_to_read, my_lines_to_skip, my_read_size, my_read_offset;
	int64_t cur_chars_read;
	char *input_UFX_name;
	unsigned char *my_buffer;
	int64_t ptr = 0;

	char cur_contig[MAXIMUM_CONTIG_SIZE], unpackedKmer[KMER_LENGTH+1], left_ext, right_ext;
	shared start_kmer_t *startKmersList = NULL, *curStartNode;

	kmer_t *cur_kmer_ptr;
	upc_file_t *input_file;

	/** Read input **/
	upc_barrier;
	inputTime -= gettime();

	///////////////////////////////////////////
	//   code for input file reading : begin //
	
	input_UFX_name = argv[1];
	nKmers = getNumKmersInUFX(input_UFX_name);
	
	avg_nKmers = nKmers / THREADS;
	rem_nKmers = nKmers % THREADS;
	
	my_lines_to_read = (MYTHREAD < rem_nKmers)? (avg_nKmers+1) : avg_nKmers;
	my_lines_to_skip = (MYTHREAD <= rem_nKmers)? (avg_nKmers * MYTHREAD + MYTHREAD) : (avg_nKmers * MYTHREAD + rem_nKmers);

	my_read_size = my_lines_to_read * LINE_SIZE;
	my_read_offset = my_lines_to_skip * LINE_SIZE;

	my_buffer =  (unsigned char*) malloc((my_read_size) * sizeof(unsigned char));
		
	input_file = upc_all_fopen(input_UFX_name, UPC_RDONLY | UPC_INDIVIDUAL_FP, 0, NULL);
	upc_all_fseek(input_file, my_read_offset*sizeof(unsigned char), UPC_SEEK_SET);
	cur_chars_read = upc_all_fread_local(input_file, my_buffer, sizeof(unsigned char), my_read_size, UPC_IN_ALLSYNC | UPC_OUT_ALLSYNC);
	upc_all_fclose(input_file);	
	printf("Thread#%d of %d: read %d kMers, skip %d kMers.\n", MYTHREAD, THREADS, my_lines_to_read, my_lines_to_skip);
		
	//   code for input file reading : end   //
	///////////////////////////////////////////
	upc_barrier;
	inputTime += gettime();

	//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//

	/** Graph construction **/
	constrTime -= gettime();
	///////////////////////////////////////////
	//  code for graph construction: begin   //
	
    /* Initialize lookup table that will be used for the DNA packing routines */
    init_LookupTable();
	/* Creates a hash table and (pre)allocates memory for the memory heap */

	//static shared hash_table_t hashtable;
	//int64_t n_buckets = nKmers * LOAD_FACTOR;
   	//hashtable.size = n_buckets;
   	//hashtable.table = (shared bucket_t*) upc_all_alloc(n_buckets , sizeof(bucket_t));	
//   	if (hashtable.table == NULL) {
//      	fprintf(stderr, "ERROR: Could not allocate memory for the hash table: %lld buckets of %lu bytes\n", n_buckets, sizeof(bucket_t));
//      	upc_global_exit(1);
//   	}
//	upc_memset(hashtable.table, 0, n_buckets * sizeof(bucket_t));  

//   	static shared memory_heap_t memory_heap;

	shared [1] kmer_t *heap;
	heap = (shared [1] kmer_t *) upc_all_alloc (nKmers, sizeof(kmer_t));

   	
//   	if (heaps[MYTHREAD].heap == NULL) {
//      	fprintf(stderr, "ERROR: Thread %d could not allocate memory for the heap!\n", MYTHREAD);
//      	upc_global_exit(1);
//   	}
	int64_t myPosInHeap = MYTHREAD;
	
	while (ptr < cur_chars_read) {
    	/* working_buffer[ptr] is the start of the current k-mer                */
     	/* so current left extension is at working_buffer[ptr+KMER_LENGTH+1]    */
     	/* and current right extension is at working_buffer[ptr+KMER_LENGTH+2]  */
      	left_ext = (char) my_buffer[ptr+KMER_LENGTH+1];
      	right_ext = (char) my_buffer[ptr+KMER_LENGTH+2];

      	/* Add k-mer to hash table */
      	//add_kmer(&hashtable, heap, &myPosInHeap, &my_buffer[ptr], left_ext, right_ext);
		add_kmer(heap, &myPosInHeap, &my_buffer[ptr], left_ext, right_ext);
		

      	/* Create also a list with the "start" kmers: nodes with F as left (backward) extension */
      	if (left_ext == 'F') {
        // 	addKmerToStartList(&heaps[MYTHREAD], &startKmersList);
      	}

      	/* Move to the next k-mer in the input working_buffer */
      	ptr += LINE_SIZE;
   	}
	
	//  code for graph construction: end     //
	///////////////////////////////////////////
	printf("Thread %d done./n");
	upc_barrier;
	constrTime += gettime();


	//debug
	if(MYTHREAD == 2){
		int i;
		for(i = 0; i < my_lines_to_read; i++){
			printf("Thread %d heap[%d] = %c%c\n", MYTHREAD, i, heap[MYTHREAD + i*THREADS].l_ext, heap[MYTHREAD + i*THREADS].r_ext);
		}


	}
	
	
	
	//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//
#if 0

	/** Graph traversal **/
	traversalTime -= gettime();
	////////////////////////////////////////////////////////////
	//  code for graph traversal and output printing: begin   //
	//  Save your output to "pgen.out"                        //
	

   	int64_t posInContig, contigID = 0, totBases = 0;

	
	char output_file_name[50];
	sprintf(output_file_name, "pgen%d.out", MYTHREAD);
	FILE *output_file = fopen(output_file_name, "w"); 
	
	/* Pick start nodes from the startKmersList */
    curStartNode = startKmersList;

    while (curStartNode != NULL ) {
        /* Need to unpack the seed first */
        cur_kmer_ptr = curStartNode->kmerPtr;
      	unpackSequence((unsigned char*) cur_kmer_ptr->kmer,  (unsigned char*) unpackedKmer, KMER_LENGTH);
      	/* Initialize current contig with the seed content */
      	memcpy(cur_contig ,unpackedKmer, KMER_LENGTH * sizeof(char));
      	posInContig = KMER_LENGTH;
      	right_ext = cur_kmer_ptr->r_ext;

      	/* Keep adding bases while not finding a terminal node */
      	while (right_ext != 'F') {
       	  	cur_contig[posInContig] = right_ext;
       	  	posInContig++;
       	  	/* At position cur_contig[posInContig-KMER_LENGTH] starts the last k-mer in the current contig */
       	  	cur_kmer_ptr = lookup_kmer(&hash_table, (const unsigned char *) &cur_contig[posInContig-KMER_LENGTH]);
       	  	right_ext = cur_kmer_ptr->r_ext;
      	}

      	/* Print the contig since we have found the corresponding terminal node */
     	cur_contig[posInContig] = '\0';
      	fprintf(output_file,"%s\n", cur_contig);
      	contigID++;
      	totBases += strlen(cur_contig);
      	/* Move to the next start node in the list */
      	curStartNode = curStartNode->next;
   }
	
	
	// close the output file
	fclose(output_file);
	
	
	// clean the allocated memory
	upc_barrier;
	
  	//printf("Traversal Finished on Thread#%d of %d threads.\n", MYTHREAD, THREADS);
		
	if(MYTHREAD == 0) {
	  //upc_free(memory_heap);
	  //upc_free(next_index);
	  //upc_free(hash_table);
	}
	
	
	upc_barrier;
	traversalTime += gettime();

	// produce a single output file
 	if(MYTHREAD == 0) {
    	output_file = fopen("pgen.out", "w");
    
   		 for(int t = 0; t < THREADS; ++ t) {
      		char str[50];
      		sprintf(str, "pgen%d.out", t);
      		FILE*in_file = fopen(str, "r");
      
      		while(fscanf(in_file, "%s", cur_contig) == 1)
        	fprintf(output_file, "%s\n", cur_contig);
       		fclose(in_file);
    	}  
    	fclose(output_file);
  	}
#endif
	//  code for graph traversal and output printing: end     //
	////////////////////////////////////////////////////////////
	upc_barrier;
	traversalTime += gettime();

	/** Print timing and output info **/
	/***** DO NOT CHANGE THIS PART ****/
	if(MYTHREAD==0){
		printf("%s: Input set: %s\n", argv[0], argv[1]);
		printf("Number of UPC threads: %d\n", THREADS);
		printf("Input reading time: %f seconds\n", inputTime);
		printf("Graph construction time: %f seconds\n", constrTime);
		printf("Graph traversal time: %f seconds\n", traversalTime);
	}
	return 0;
}
