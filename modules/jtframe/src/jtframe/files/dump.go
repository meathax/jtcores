package files

import(
	"path/filepath"
	"fmt"
	"os"
	"strings"
)

func dump_qip(all []string) error {
	fout, err := os.Create("files.qip")
	if err != nil { return err }
	defer fout.Close()
	for _, each := range all {
		filetype := ""
		switch filepath.Ext(each) {
		case ".sv":
			filetype = "SYSTEMVERILOG_FILE"
		case ".vhd":
			filetype = "VHDL_FILE"
		case ".v":
			filetype = "VERILOG_FILE"
		case ".qip":
			filetype = "QIP_FILE"
		case ".sdc":
			filetype = "SDC_FILE"
		default:
			return fmt.Errorf("JTFILES: unsupported file extension %s in file %s", filepath.Ext(each), each)
		}
		// Quartus reads the QIP as Tcl. On Windows, filepath.Join/Clean produce backslash paths, and an unquoted Tcl bareword applies backslash escape substitution (drops the backslash, or turns \r \n \t into real control chars), corrupting every absolute path here and making quartus_map report every source file "missing". Forward slashes are accepted by Quartus on Windows (SEARCH_PATH already uses them) and are not special to Tcl.
		slashed := filepath.ToSlash(each)
		aux := "set_global_assignment -name " + filetype
		if args.Rel {
			aux = aux + "[file join $::quartus(qip_path) " + slashed + "]"
		} else {
			aux = aux + " " + slashed
		}
		fmt.Fprintln(fout, aux)
	}
	return nil
}

func dump_sim(all []string ) error {
	fout, err := os.Create( "game.f" )
	if err != nil { return err }
	fout_vhdl, err := os.Create("jtsim_vhdl.f")
	if err != nil { return err }
	defer fout.Close()
	defer fout_vhdl.Close()
	for _, each := range all {
		// Same Windows backslash-path issue as dump_qip: game.f/jtsim_vhdl.f
		// are plain -f file lists, and downstream tooling (jtsim's use of
		// `echo`/`sed` under MSYS bash) treats backslashes as escapes too,
		// silently eating every path separator. Emit forward slashes.
		slashed := filepath.ToSlash(each)
		dump := true
		switch filepath.Ext(each) {
		case ".sv", ".v":
			dump = true
		case ".qip",".sdc":
			dump = false
		case ".vhd":
			fmt.Fprintln(fout_vhdl, slashed)
			dump = false
		default:
			return fmt.Errorf("JTFILES: unsupported file extension %s in file %s", filepath.Ext(each), each)
		}
		if dump {
			fmt.Fprintln(fout, slashed)
		}
	}
	return nil
}

func dump_plain(all []string ) error {
	fout, err := os.Create( "files" )
	if err != nil { return err }
	defer fout.Close()
	jtroot := filepath.ToSlash(os.Getenv("JTROOT"))+"/"
	for _, each := range all {
		each = strings.TrimPrefix(filepath.ToSlash(each), jtroot)
		fmt.Fprintln(fout, each)
	}
	return nil
}