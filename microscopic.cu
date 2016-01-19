#include <cuda.h>
#include <stdio.h>
#include "datadef.h"
#include "LCRNG.cuh"

__global__ void microscopic_kernel(unsigned N, unsigned n_isotopes, unsigned n_columns, unsigned* remap, unsigned* isonum, unsigned * index, float * main_E_grid, unsigned * rn_bank, float * E, float * xs_data_MT , unsigned * xs_MT_numbers_total, unsigned * xs_MT_numbers,  float* xs_data_Q, unsigned * rxn, float* Q, unsigned* done){


	int tid_in = threadIdx.x+blockIdx.x*blockDim.x;
	if (tid_in >= N){return;}

		// declare shared variables
	__shared__ 	unsigned			n_isotopes;				
	//__shared__ 	unsigned			energy_grid_len;		
	__shared__ 	unsigned			total_reaction_channels;
	//__shared__ 	unsigned*			rxn_numbers;			
	//__shared__ 	unsigned*			rxn_numbers_total;		
	__shared__ 	float*				energy_grid;			
	//__shared__ 	float*				rxn_Q;						
	__shared__ 	float*				xs;						
	//__shared__ 	float*				awr;					
	//__shared__ 	float*				temp;					
	//__shared__ 	dist_container*		dist_scatter;			
	//__shared__ 	dist_container*		dist_energy; 
	__shared__	spatial_data*		space;	
	__shared__	unsigned*			rxn;	
	__shared__	float*				E;		
	//__shared__	float*				Q;		
	__shared__	unsigned*			rn_bank;
	//__shared__	unsigned*			cellnum;
	__shared__	unsigned*			matnum;	
	__shared__	unsigned*			isonum;	
	//__shared__	unsigned*			yield;	
	//__shared__	float*				weight;	
	__shared__	unsigned*			index;	

	// have thread 0 of block copy all pointers and static info into shared memory
	if (threadIdx.x == 0){
		n_isotopes					= d_xsdata[0].n_isotopes;								
		//energy_grid_len				= d_xsdata[0].energy_grid_len;				
		total_reaction_channels		= d_xsdata[0].total_reaction_channels;
		//rxn_numbers 				= d_xsdata[0].rxn_numbers;						
		//rxn_numbers_total			= d_xsdata[0].rxn_numbers_total;					
		energy_grid 				= d_xsdata[0].energy_grid;						
		//rxn_Q 						= d_xsdata[0].Q;												
		xs 							= d_xsdata[0].xs;												
		//awr 						= d_xsdata[0].awr;										
		//temp 						= d_xsdata[0].temp;										
		//dist_scatter 				= d_xsdata[0].dist_scatter;						
		//dist_energy 				= d_xsdata[0].dist_energy; 
		space						= d_particles[0].space;
		rxn							= d_particles[0].rxn;
		E							= d_particles[0].E;
		//Q							= d_particles[0].Q;	
		rn_bank						= d_particles[0].rn_bank;
		//cellnum						= d_particles[0].cellnum;
		matnum						= d_particles[0].matnum;
		isonum						= d_particles[0].isonum;
		//yield						= d_particles[0].yield;
		//weight						= d_particles[0].weight;
		index						= d_particles[0].index;
	}

	// make sure shared loads happen before anything else
	__syncthreads();
	

	unsigned 	this_rxn 		= rxn[tid_in];
	if 		(this_rxn>=900 | this_rxn==800 | this_rxn == 801){
		return;  //return if flagged to resample or leaked (leak can be in here since set by macro and remap hasn't been done)
	} 
	else if (this_rxn==0){
		this_rxn = 999999999;
	}
	else{
		this_rxn = 999999999;
		printf("microscopic got reaction between 1 and 799 from macro!\n");
	}
	
	//remap
	int tid=remap[tid_in];
	//printf("tid %u remapped_tid %u\n",tid_in,tid);

	// load from array
	unsigned 	this_tope 		= isonum[tid];
	unsigned 	dex 			= index[tid];
	unsigned 	tope_beginning;
	unsigned 	tope_ending;
	unsigned 	this_dex;
	float 		this_E  		= E[tid];
	unsigned	rn 				= rn_bank[tid];
	float 		rn1 			= get_rand(&rn);
	float 		cum_prob 		= 0.0;
	float 		this_Q 			= 0.0;
	unsigned 	k 				= 0;
	

	if (this_tope == 0){  //first isotope
		tope_beginning = n_isotopes + 0;
		tope_ending    = n_isotopes + xs_MT_numbers_total[0]-1;
	}
	else if(this_tope>=n_isotopes){
		printf("micro - ISOTOPE NUMBER FROM MACRO > NUMBER OF ISOTOPES!  n_isotopes %u tope %u\n",n_isotopes,this_tope);
	}
	else{  //interior space
		tope_beginning = n_isotopes + xs_MT_numbers_total[this_tope-1];
		tope_ending    = n_isotopes + xs_MT_numbers_total[this_tope]-1;
	}

	float xs_total = 0.0;
	float e0 = main_E_grid[dex];
	float e1 = main_E_grid[dex+1];
	float t0,t1;

	// compute the total microscopic cross section for this material
	// linearly interpolate, dex is the row number
	t0 			= xs_data_MT[n_columns* dex    + this_tope];     
	t1 			= xs_data_MT[n_columns*(dex+1) + this_tope];
	xs_total 	= (t1-t0)/(e1-e0)*(this_E-e0) + t0 ;    

	// determine the reaction for this isotope
	for(k=tope_beginning; k<=tope_ending; k++){
		//linearly interpolate
		t0 = xs_data_MT[n_columns* dex    + k];     
		t1 = xs_data_MT[n_columns*(dex+1) + k];
		cum_prob += ( (t1-t0)/(e1-e0)*(this_E-e0) + t0 ) / xs_total;
		if(rn1 <= cum_prob){
			// reactions happen in reaction k
			this_rxn = xs_MT_numbers[k];
			//printf("tope %u beg/end %u %u rxn %u cum_prob %6.4E rn1 %6.4E this_E %6.4E (tot,es,91,abs) %6.4E %6.4E %6.4E %6.4E\n",this_tope,tope_beginning,tope_ending,this_rxn,cum_prob,rn1,this_E,xs_data_MT[n_columns* dex    + 0],xs_data_MT[n_columns* dex    + 1],xs_data_MT[n_columns* dex    + 46],xs_data_MT[n_columns* dex    + 47]);
			this_Q   = xs_data_Q[k];
			this_dex = n_columns* dex + k;
			break;
		}
	}

	if(this_rxn == 999999999){ // there is a gap in between the last MT and the total cross section, remap the rn to fit into the available data (effectively rescales the total cross section so everything adds up to it, if things aren't samples the first time around)
		printf("micro - REACTION NOT SAMPLED CORRECTLY! tope=%u E=%10.8E dex=%u rxn=%u cum_prob=%30.28E rn1=%30.28E\n",this_tope, this_E, dex, this_rxn, cum_prob,rn1); //most likely becasue rn1=1.0
		rn1 = rn1 * cum_prob;
		cum_prob = 0.0;
		for(k=tope_beginning; k<tope_ending; k++){
			//lienarly interpolate
			t0 = xs_data_MT[n_columns* dex    + k];     
			t1 = xs_data_MT[n_columns*(dex+1) + k];
			cum_prob += ( (t1-t0)/(e1-e0)*(this_E-e0) + t0 ) / xs_total;
			if(rn1 <= cum_prob){
				// reactions happen in reaction k
				this_rxn = xs_MT_numbers[k];
				this_Q   = xs_data_Q[k];
				this_dex = n_columns * dex + k;
				break;
			}
		}
	}

	//if( this_rxn >= 811 & this_rxn<850 & this_rxn!=818 ){printf("microscopic sampled tid %u rxn %d energy %6.4E\n",tid,this_rxn,this_E);}
	//printf("%u\n",this_rxn);
	if(this_rxn == 3 | this_rxn==4 | this_rxn ==5 | this_rxn ==10 | this_rxn ==27){
		printf("MT=%u!!!, changing to 1102...\n",this_rxn);
		this_rxn = 1102;
	}
	//if(this_rxn==56){printf("MT=56 at E %10.8E\n",this_E);}
	rxn[tid_in] = this_rxn;
	Q[tid] 	 = this_Q;
	rn_bank[tid] = rn;
	//also write MT array index to dex instead of energy vector index
	index[tid] = this_dex;


}

void microscopic( unsigned NUM_THREADS, unsigned N, unsigned n_isotopes, unsigned n_columns, unsigned* remap,unsigned* isonum, unsigned * index, float * main_E_grid, unsigned * rn_bank, float * E, float * xs_data_MT , unsigned * xs_MT_numbers_total, unsigned * xs_MT_numbers,  float* xs_data_Q, unsigned * rxn, float* Q, unsigned* done){

	unsigned blks = ( N + NUM_THREADS - 1 ) / NUM_THREADS;

	microscopic_kernel <<< blks, NUM_THREADS >>> ( N,  n_isotopes, n_columns, remap, isonum, index, main_E_grid, rn_bank, E, xs_data_MT , xs_MT_numbers_total, xs_MT_numbers, xs_data_Q, rxn, Q, done);
	cudaThreadSynchronize();

}

