
#pragma once

class ForwardTable {
	struct Entry {
		uintptr_t from, to;
		Entry(uintptr_t f = 0, uintptr_t t = 0) : from(f), to(t) { }
	};

	static const int trimbits = 3; //trim the bottom bits of the pointer since they're always 0 anyway

	uintptr_t size; //how many slots
	uintptr_t num;  //how many are used
	uintptr_t mask;
	Entry * table;

public:
	ForwardTable() : size(0), mask(0), table(NULL) { }
	ForwardTable(uintptr_t s){ init(s); }
	~ForwardTable(){
		clear();
	}

	void init(uintptr_t s){
		clear();
		size = ceil_power2(s)*4;
		mask = size-1;
		table = new Entry[size];
	}

	void clear(){
		if(table)
			delete[] table;
		table = NULL;
	}

	void clean(){
		for(uintptr_t i = 0; i < size; i++)
			table[i] = Entry();
	}

	template<typename tObj>
	void set(tObj * fromptr, tObj * toptr){ return set((uintptr_t) fromptr, (uintptr_t) toptr); }
	void set(uintptr_t from, uintptr_t to){
		uintptr_t i = mix(from) & mask;
		while(table[i].from != 0)
			i = (i+1) & mask;
		table[i] = Entry(from, to);
		num++;
	}

	template<typename tObj>
	tObj *    get(tObj * fromptr){ return (tObj *) get((uintptr_t) fromptr); }
	uintptr_t get(uintptr_t from){
		for(uintptr_t i = mix(from) & mask; table[i].from; i = (i+1) & mask)
			if(table[i].from == from)
				return table[i].to;
		return 0;
	}

	//give a good distribution over the hash space to have fewer collisions
	static uintptr_t mix(uintptr_t in){
		return (in >> trimbits);
	}
};

