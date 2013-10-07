CC=vcs

FLAGS=-sverilog -debug -assert filter -assert enable_diag

default: student

student: top.sv tb.sv processor.sv memory.sv 
	$(CC) $(FLAGS) top.sv tb.sv processor.sv memory.sv

public: top.sv TA_tb.sv processor.sv memory.sv
	$(CC) $(FLAGS) top.sv TA_tb.sv processor.sv memory.sv

clean:
	rm -rf simv
	rm -rf simv.daidir
	rm -rf csrc
	rm -rf ucli.key
	rm -rf simv.vdb
	rm -rf DVEfiles
	rm -rf inter.vpd
