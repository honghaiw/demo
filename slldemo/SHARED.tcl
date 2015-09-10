#-----------------------------------------------------------------------------
# FILE
#               SHARED.tcl
#
# OWNER
#
#               hjdong
# HISTORY
#
#               First release, 12/01/2004
#
# PURPOSE
#
#               This file integrates shared data and behaviors.
#
# DESCRIPTION
#
#               The following files will be integrated in this file:
#-----------------------------------------------------------------------------
component SHARED \
data include {
%%	include SHARED/Parse_Object
%%}\
behavior Global_Subroutine {
%%      puts $OUTPUT [query Parse_Object behavior Subroutines]
}\
behavior Global_Proc {
%% proc CPU_Overload_Control_Check { OUTPUT dataview_name } {
	if Determine_Traffic_Ctrl("LDAP_Call") != OLC_Action_Normal
	then
%% if {$dataview_name == "Hier_Req"} {
		if Secondary_Account_ID == "UPDINDEXDB"
		then
			incr Glb_Service_Measurement_Rec.LDAP_IdxReq_Flt_By_OLC
		else
			incr Glb_Service_Measurement_Rec.LDAP_HierReq_Flt_By_OLC
		end if
%% }
%% if {$dataview_name == "req_idx"} {
		incr Glb_Service_Measurement_Rec.LDAP_IdxReq_Flt_By_OLC
		incr Req_Idx_Snt_Fail_Msg_Num
%% }
%% if {$dataview_name == "req_group_info"} {
		incr Glb_Service_Measurement_Rec.LDAP_HierReq_Flt_By_OLC
%% }
		set LDAP_Return = ${dataview_name}!send_read_failed (@.instance,
			@.request_id,
			e_busy)
		next state Communication_LDAP
		next event LDAP_Terminate_Call
		return
	end if
%% }
}\
behavior Client_Global_Initialize {
%%set SPA_NAME \"$env(SP)\"
  	set Glb_SPA_NAME = ${SPA_NAME}
	set Glb_Report_Title = "REPT SPA=" : Glb_SPA_NAME
}\
behavior LDAP_Req_Data_Parse_Function {
#-------------------------------------------------------------------------
# Function      : LDAP_ReqData_Key_Parse
#
# Description   : This funtion will parse input string delimited
#                 by input delimiter,then insert into a table,
#                 and the input string should be name=value pairs.
#               v10su13, 66405, enhance to parse paramters without name.
#               the parameter value will be stored in LDAP_ReqData_Key_tbl using index start from "1"
#
# Parameter
#       Input   : Input_String string
#                 Input_Delimiter string(1)
#                v10su13, 66405
#                 Input_With_Para_Name_Flag flag
#       Output  : flag
#-------------------------------------------------------------------------

def_function LDAP_ReqData_Key_Parse (
		Input_Delimiter				string(1),
		Input_String				string,
		Input_With_Para_Name_Flag		flag
	) flag
dynamic
	Local_string1				string
	Local_string2				string
	Local_Loop_Counter			counter
end dynamic
	if Input_String == "" || Input_Delimiter == ""
	then
		return(false)
	end if
	if Glb_LDAP_Max_Loop == 0
	then
		set Glb_LDAP_Max_Loop = 100
	end if

	set Local_Loop_Counter = Glb_LDAP_Max_Loop

	Parse_Object(Input_Delimiter, Input_String)
	while Trim_Blanks(Glb_Remainder) != ""
	do
		set Local_string1 = Glb_Remainder
		set Local_string2 = Glb_Parsed
		if Trim_Blanks(Glb_Parsed) != "" || !Input_With_Para_Name_Flag
		then
			# the parameter value will be stored in LDAP_ReqData_Key_tbl using index start from "1"
			if(Input_With_Para_Name_Flag)
			then
				Parse_Object("=", Glb_Parsed)
				if find("=", Local_string2) == 0 || Glb_Parsed == "" #no "=" or name missed
				then
					set Glb_GSL_Error_Return = "Error: name of name-value pair missed in dataview key!"
					return(false)
				end if
				set Glb_Parsed = Trim_Blanks(Glb_Parsed)
				set Glb_Parsed = map(Glb_Parsed,
					"abcdefghijklmnopqrstuvwxyz",
					"ABCDEFGHIJKLMNOPQRSTUVWXYZ")
			else
				set Glb_Remainder = Glb_Parsed
				set Glb_Parsed = string(Glb_LDAP_Max_Loop - Local_Loop_Counter + 1)
			end if

			if !element_exists(LDAP_ReqData_Key_tbl, Glb_Parsed)
			then
				set LDAP_ReqData_Key_Field_Record.Key_Value = Trim_Blanks(Glb_Remainder)
				insert LDAP_ReqData_Key_Field_Record into LDAP_ReqData_Key_tbl at Glb_Parsed
			else
				set Glb_GSL_Error_Return = "Error: duplicate label in input parameters!"
				return(false)
			end if
		end if
		# limit loop times
		decr Local_Loop_Counter
		if Local_Loop_Counter == 0
		then
			set Glb_GSL_Error_Return = "Error: too many input parameters!"
			return(false)
		end if
		# continue Parse ...
		Parse_Object(Input_Delimiter, Local_string1)
	end while
	# if format with no parameter name, null value need insert also
	if Trim_Blanks(Glb_Parsed) != "" || !Input_With_Para_Name_Flag
	then
		# enhance to parse paramters without name.
		# the parameter value will be stored in LDAP_ReqData_Key_tbl using index start from "1"
		if(Input_With_Para_Name_Flag)
		then
			set Local_string2 = Glb_Parsed
			Parse_Object("=", Glb_Parsed)
			if find("=", Local_string2) == 0 || Glb_Parsed == "" #no "=" or name missed
			then
				set Glb_GSL_Error_Return = "Error: name of name-value pair missed in dataview key!"
				return(false)
			end if
			set Glb_Parsed = Trim_Blanks(Glb_Parsed)
			set Glb_Parsed = map(Glb_Parsed,
				"abcdefghijklmnopqrstuvwxyz",
				"ABCDEFGHIJKLMNOPQRSTUVWXYZ")
		else
			set Glb_Remainder = Glb_Parsed
			set Glb_Parsed = string(Glb_LDAP_Max_Loop - Local_Loop_Counter + 1)
		end if

		if !element_exists(LDAP_ReqData_Key_tbl, Glb_Parsed)
		then
			set LDAP_ReqData_Key_Field_Record.Key_Value = Trim_Blanks(Glb_Remainder)
			insert LDAP_ReqData_Key_Field_Record into LDAP_ReqData_Key_tbl at Glb_Parsed
		else
			set Glb_GSL_Error_Return = "Error: duplicate label in input parameters!"
			return(false)
		end if

	end if
	return(true)
end def_function LDAP_ReqData_Key_Parse
}\
behavior Check_Every_1S_Timer_Function {
def_function Check_DataView_RTDB_Attach_Status() flag
        loop Inter_eCS_COMM
                if (Hierarchy_Request_Dataview_Name != "") && Glb_INIT_Hier_Req_DATAVIEW_Instance == 0
                then
                        set Glb_INIT_Hier_Req_DATAVIEW_Attach_Ret_Val 
                            = Hier_Req!attach_owner(Hierarchy_Request_Dataview_Name)
                        if (Glb_INIT_Hier_Req_DATAVIEW_Attach_Ret_Val == e_a_okay)
                        then
                                set Glb_INIT_Hier_Req_DATAVIEW_Instance
                                    = Hier_Req!get_instance(Hierarchy_Request_Dataview_Name)
      
                        else
                                reset Glb_INIT_Hier_Req_DATAVIEW_Instance
                        end if
                end if
                #SP27.9 VFCZ Feature 70577
                if (Req_Group_Info_Dataview_Name!= "") && Glb_INIT_Req_Group_Info_DataView_Instance == 0
                then
                        set Glb_INIT_Req_Group_Info_DataView_Ret_Val 
                                = req_group_info!attach_owner(Req_Group_Info_Dataview_Name)
                        if (Glb_INIT_Req_Group_Info_DataView_Ret_Val == e_a_okay)
                        then
                                set Glb_INIT_Req_Group_Info_DataView_Instance
                                        = req_group_info!get_instance(Req_Group_Info_Dataview_Name)
                        else
                                reset Glb_INIT_Req_Group_Info_DataView_Instance
                        end if

                end if
                # VzW 72138
                if (Request_Index_Dataview_Name != "") && Glb_INIT_Req_Index_DATAVIEW_Instance == 0
                then
                        set Glb_INIT_Req_Index_DATAVIEW_Attach_Ret_Val
                            = req_idx!attach_owner(Request_Index_Dataview_Name)
                        if (Glb_INIT_Req_Index_DATAVIEW_Attach_Ret_Val == e_a_okay)
                        then
                                set Glb_INIT_Req_Index_DATAVIEW_Instance
                                    = req_idx!get_instance(Request_Index_Dataview_Name)
                        else
                                reset Glb_INIT_Req_Index_DATAVIEW_Instance
                        end if
                end if
        end loop Inter_eCS_COMM
                if GLB_GPRSSIM_Instance == 0
                then
                             # V7.1 Feature 9830
                             # Check Common Parameters table for RTDB mode
                             test GPRSSIM_RTDB_Mode
                             case 0
                                     # In Memory - Attached
                                     set Glb_RTDB_Attach_Ret_Val = GPRSSIM!attach(GLB_GPRSSIM_Table_Name)
                                     set GLB_GPRSSIM_In_Memory
                             case 1
                                     # In Memory - Detached
                                     set Glb_RTDB_Attach_Ret_Val =
                                         GPRSSIM!attach_no_cache(GLB_GPRSSIM_Table_Name  )
                                     reset GLB_GPRSSIM_In_Memory
                             case 2
                                     # Disk Based
                                     set Glb_RTDB_Attach_Ret_Val = GPRSSIM!attach(GLB_GPRSSIM_Table_Name )
                                     reset GLB_GPRSSIM_In_Memory

                             other
                                     # RTDB Not used
                                     # Do not attach and set return value to not error
                                     set Glb_RTDB_Attach_Ret_Val = e_no_error
                                     set GLB_GPRSSIM_Not_Used
                             end test

                        if Glb_RTDB_Attach_Ret_Val == e_a_okay
                        then
                                set GLB_GPRSSIM_Instance =
                                        GPRSSIM!get_instance(GLB_GPRSSIM_Table_Name )

                                if GLB_GPRSSIM_Instance != 0
                                then
                                        # RTDB instance is valid
                                        set GLB_GPRSSIM_Attached
                                else
                                        # RTDB instance is zero
                                        # Not a valid value for an attached RTDB
                                        reset GLB_GPRSSIM_Attached
                                        # Schedule a near immediate report
                                        # of this failure
                                end if

                        else
                                # Failed to attach to the GPRSSIM RTDB
                                reset GLB_GPRSSIM_Attached
                        end if
                end if

        return (true)
end def_function Check_DataView_RTDB_Attach_Status

def_function Print_DataView_Msg_Num() flag
        if Req_Idx_Rec_Msg_Num != 0
        then
                print("In msg: ",Req_Idx_Rec_Msg_Num)
                print("In msg to ln: ",Req_Idx_Rec_Msg_Num_Broadcast)
                print("In msg to grp: ",Req_Idx_Rec_Msg_Num_U_Or_Q)
                print("In Res 00: ", Req_Idx_Snt_Suc_00_Msg_Num)
                print("In Res 00 to ln: ", Req_Idx_Snt_Suc_00_Msg_Num_Broadcast)
                print("In Res 00 to grp: ", Req_Idx_Snt_Suc_00_Msg_Num_U_Or_Q)
                print("In Res othr: ", Req_Idx_Snt_Suc_Non_00_Msg_Num)
                print("In Res othr to ln: ", Req_Idx_Snt_Suc_Non_00_Msg_Num_Broadcast)
                print("In Res othr to grp: ", Req_Idx_Snt_Suc_Non_00_Msg_Num_U_Or_Q)
                print("In Res Fail: ",Req_Idx_Snt_Fail_Msg_Num)
                print("In Res Fail to ln: ",Req_Idx_Snt_Fail_Msg_Num_Broadcast)
                print("In Res Fail to grp: ",Req_Idx_Snt_Fail_Msg_Num_U_Or_Q)
                print("Out msg: ",Data_Req_Snt_Msg_Num)
                print("Out msg to ln: ",Data_Req_Snt_Msg_Num_Broadcast)
                print("Out msg to grp: ",Data_Req_Snt_Msg_Num_U_Or_Q)
                print("Out Res 00: ", Data_Req_Rec_Suc_00_Msg_Num)
                print("Out Res 00 to ln: ", Data_Req_Rec_Suc_00_Msg_Num_Broadcast)
                print("Out Res 00 to grp: ", Data_Req_Rec_Suc_00_Msg_Num_U_Or_Q)
                print("Out Res 02: ", Data_Req_Rec_Suc_02_Msg_Num)
                print("Out Res 02 to ln: ", Data_Req_Rec_Suc_02_Msg_Num_Broadcast)
                print("Out Res 02 to grp: ", Data_Req_Rec_Suc_02_Msg_Num_U_Or_Q)
                print("Out Res 03: ", Data_Req_Rec_Suc_03_Msg_Num)
                print("Out Res 03 to ln: ", Data_Req_Rec_Suc_03_Msg_Num_Broadcast)
                print("Out Res 03 to grp: ", Data_Req_Rec_Suc_03_Msg_Num_U_Or_Q)
                print("Out Res othr: ", Data_Req_Rec_Suc_Oth_Msg_Num)
                print("Out Res othr to ln: ", Data_Req_Rec_Suc_Oth_Msg_Num_Broadcast)
                print("Out Res othr to grp: ", Data_Req_Rec_Suc_Oth_Msg_Num_U_Or_Q)
                print("Out Res Fail: ",Data_Req_Rec_Fail_Msg_Num)
                print("Out Res Fail to ln: ",Data_Req_Rec_Fail_Msg_Num_Broadcast)
                print("Out Res Fail to grp: ",Data_Req_Rec_Fail_Msg_Num_U_Or_Q)
        end if
        return (true)
end def_function Print_DataView_Msg_Num

def_function Reset_DataView_Msg_Num() flag
        if Req_Idx_Rec_Msg_Num != 0
        then
                # clear every month
                set Glb_Temp_Counter_1 = 2678400 #86400*31
                if Glb_Current_Second % Glb_Temp_Counter_1 == 0
                then
                        reset Req_Idx_Rec_Msg_Num
                        reset Req_Idx_Rec_Msg_Num_Broadcast
                        reset Req_Idx_Rec_Msg_Num_U_Or_Q
                        reset Req_Idx_Snt_Suc_00_Msg_Num
                        reset Req_Idx_Snt_Suc_00_Msg_Num_Broadcast
                        reset Req_Idx_Snt_Suc_00_Msg_Num_U_Or_Q
                        reset Req_Idx_Snt_Suc_Non_00_Msg_Num
                        reset Req_Idx_Snt_Suc_Non_00_Msg_Num_Broadcast
                        reset Req_Idx_Snt_Suc_Non_00_Msg_Num_U_Or_Q
                        reset Req_Idx_Snt_Fail_Msg_Num
                        reset Req_Idx_Snt_Fail_Msg_Num_Broadcast
                        reset Req_Idx_Snt_Fail_Msg_Num_U_Or_Q
                        reset Data_Req_Snt_Msg_Num
                        reset Data_Req_Snt_Msg_Num_Broadcast
                        reset Data_Req_Snt_Msg_Num_U_Or_Q
                        reset Data_Req_Rec_Suc_00_Msg_Num
                        reset Data_Req_Rec_Suc_00_Msg_Num_Broadcast
                        reset Data_Req_Rec_Suc_00_Msg_Num_U_Or_Q
                        reset Data_Req_Rec_Suc_02_Msg_Num
                        reset Data_Req_Rec_Suc_02_Msg_Num_Broadcast
                        reset Data_Req_Rec_Suc_02_Msg_Num_U_Or_Q
                        reset Data_Req_Rec_Suc_03_Msg_Num
                        reset Data_Req_Rec_Suc_03_Msg_Num_Broadcast
                        reset Data_Req_Rec_Suc_03_Msg_Num_U_Or_Q
                        reset Data_Req_Rec_Suc_Oth_Msg_Num
                        reset Data_Req_Rec_Suc_Oth_Msg_Num_Broadcast
                        reset Data_Req_Rec_Suc_Oth_Msg_Num_U_Or_Q
                        reset Data_Req_Rec_Fail_Msg_Num
                        reset Data_Req_Rec_Fail_Msg_Num_Broadcast
                        reset Data_Req_Rec_Fail_Msg_Num_U_Or_Q
                end if
        end if
        return (true)
end def_function Reset_DataView_Msg_Num
}\
behavior IDX_QRY_FSM_Function {
#------------------------------------------------------------------------------
# Function:     Get_SCP_Info
#
# Description:  Prepare host scp info and alternative scp info to return.
#               add in SP28.5 72544
#------------------------------------------------------------------------------
def_function Get_SCP_Info () flag
dynamic
	Local_SCP_Name				string
	Local_IMSI1				string
	#73254
        Local_E_IMSI1                           string
        Local_E_IMSI2                           string
        Local_UA                                string
        Local_MDN                               string
end dynamic
	if element_exists(LDAP_ReqData_Key_tbl, "MDN")
	then
		set Local_MDN = LDAP_ReqData_Key_tbl["MDN"].Key_Value
	end if
	if element_exists(LDAP_ReqData_Key_tbl, "IMSI1")
	then
		set Local_IMSI1 = LDAP_ReqData_Key_tbl["IMSI1"].Key_Value
	end if
	#SP28.7 VzW 73254
        if element_exists(LDAP_ReqData_Key_tbl, "E_IMSI1")
        then
                set Local_E_IMSI1 = LDAP_ReqData_Key_tbl["E_IMSI1"].Key_Value
        end if
        if element_exists(LDAP_ReqData_Key_tbl, "E_IMSI2")
        then
                set Local_E_IMSI2 = LDAP_ReqData_Key_tbl["E_IMSI2"].Key_Value
        end if
        if element_exists(LDAP_ReqData_Key_tbl, "UA")
        then
                set Local_UA = LDAP_ReqData_Key_tbl["UA"].Key_Value
        end if

	if element_exists(LDAP_ReqData_Key_tbl, "SCP_NAME")
	then
		set Local_SCP_Name = LDAP_ReqData_Key_tbl["SCP_NAME"].Key_Value
	end if
	if element_exists(LDAP_ReqData_Key_tbl, "IS_ASCP")
		&& LDAP_ReqData_Key_tbl["IS_ASCP"].Key_Value == "Y"
	then
		if Alternative_SCP_Info.SCP_Name == ""
		then
			set Alternative_SCP_Info.SCP_Name = Local_SCP_Name
			if element_exists(LDAP_ReqData_Key_tbl, "SERVICE_TYPE")
			then
				set Alternative_SCP_Info.Service_Type =
					counter(LDAP_ReqData_Key_tbl["SERVICE_TYPE"].Key_Value)
			end if
			set Alternative_SCP_Info.IMSI1 = Local_IMSI1
			#SP28.7 VzW 73254
                        set Alternative_SCP_Info.E_IMSI1 = Local_E_IMSI1
                        set Alternative_SCP_Info.E_IMSI2 = Local_E_IMSI2
                        set Alternative_SCP_Info.UA = Local_UA
			incr Useful_Index_Data_Num
		end if
	elif Host_SCP_Info.SCP_Name == ""
	then
		set Host_SCP_Info.SCP_Name = Local_SCP_Name
		set Host_SCP_Info.IMSI1 = Local_IMSI1
		#SP28.7 VzW 73254
                set Host_SCP_Info.E_IMSI1 = Local_E_IMSI1
                set Host_SCP_Info.E_IMSI2 = Local_E_IMSI2
                set Host_SCP_Info.UA = Local_UA
		incr Useful_Index_Data_Num
	end if
	#73254
        if First_MDN == ""
        then
                set First_MDN = Local_MDN
        end if

        if Local_MDN != First_MDN && Local_UA == First_MDN
        then
                set MDN = Local_MDN
        else
                set MDN = First_MDN
        end if
	return(true)
end def_function Get_SCP_Info
}\
behavior Not_Keep_Old_ID2MDN_Info_Function {
#IMR403540
#----------------------------------------------------------------
def_function Not_Keep_Old_ID2MDN_Info (
		Input_Op				string
	) flag
	if element_exists(EPPSMFlexi_Feature_tbl, "Keep_Old_ID2MDN_Info")
		&& EPPSMFlexi_Feature_tbl["Keep_Old_ID2MDN_Info"].Feature_Status == "Enable"
	then
		return(false)
	end if 
	if Input_Op == any("0", "2", "5")
	then
		return(true)
	end if
	return(false)
end def_function Not_Keep_Old_ID2MDN_Info
}\
data Global_Shared {
	#--------------------------------------------------------------
	# Parse_Object Global Dynamic Data
	#--------------------------------------------------------------
	Glb_Parse_Temp_Count			counter
	Glb_Parsed				string
	Glb_Remainder				string

	Glb_Service_Admin_Customer_Index	counter
	GSL_Report_Title			string	# 304

	#v10.12 65894
	Glb_Temp_String1			string
	Glb_Temp_String2			string
	Glb_Temp_String3			string
	Glb_Temp_Counter_1			counter
	Glb_Temp_String_Parsed			string	#SP28.16 RDAF729606
	Glb_Temp_Flag_1				flag
	Glb_DEBUG_LEVEL				counter
	Glb_RTDB_Operation_Assert_Title		string
	Glb_GSL_Error_Return			string
	Glb_Internal_Operation_Assert_Title	string

	# SP28.14 75195 
	Glb_RTDB_Data_Assert_Title	        string  #103
	#SP28.6 72000
	Glb_Best_Match				match_data
	Glb_Function_Result			flag
	Glb_Hierarchy_Structure_SPI_tbl		spi_hierarchy_structure_table
	Glb_Branch_Acc_List_tbl			Account_ID_List_Table
	Glb_Secondary_Acc_tbl			hash table (string(24))    record {}

	# sp27.7 VFGH feature 69723
	Glb_SPA_NAME				string

	#R27.7 Inter-spa commu & 3D tool test code
	spi_protocol_bound			protocol_bound_record
	spi_protocol_handle			bound_return
	Glb_InterSPA_cargo_Flag			flag
	Glb_More_Account_ID_tbl			spi_more_account_id_tbl
	Glb_Family_Group_ID_tbl			spi_family_group_id_table #SP28.9 73335
	Glb_Qry_Grp_Host_Name_Req_Rec		spi_query_group_host_name_request_message
	Glb_Qry_Grp_Host_Name_Rsp_Rec		spi_query_group_host_name_response_message
	Glb_spi_Encoded_rst			itu_tcap_enc_bi_return
	Glb_Qry_Grp_Host_Name_Req_Dec		spi_query_group_host_name_request_message_dec_bi_return
	# SP27.9 VFCZ feature 70577
	Glb_Service_Measurement_Rec		Service_Measurement_Rec_Type
	Glb_Service_Measurement_Interval	counter
	Request_Generate_Service_Measurement    def_event {}
	Service_Measurement_Handling		Service_Measurement_Handling_Type

	# VzW 72138
	Glb_Inter_HOST_LDAP_Link_tbl		Glb_Inter_HOST_LDAP_Link_Table
	Glb_Inter_HOST_DR_Dataview_Attach_By_Initialize	flag
	Request_Inter_HOST_LDAP_Link_Check_Result    def_event {
		Available				flag,
	}
	# VzW 72138 end
	# VzW 72139
	Request_Inter_HOST_LDAP_Link_Check    def_event {
		Remote_SCP_Name				string,
	}

	#R28.5 72113
	Check_Server_Name_Need_Attach    def_event {}
	Get_IDX_QRY_FSM_Index    def_event {}
	Request_Self_Learning_Healing    def_event {
		Customer_Call_ID			counter,
		ID					string,
		ID_Type					string,
		Ind                                     string, #73254
                Learning_Healing_Type                   Learning_Healing_Enum_Type,#73494	
        }
	Self_Learning_Healing    def_event {
		ID					string,
		ID_Type					string,
		Ind                                     string, #73254
	}
	Self_Learning_Healing_Result    def_event {
		Result					string,
		Data					string,
	}

	Glb_IDX_QRY_FSM_Customer_Index		counter
	Glb_LDAP_Return				ldap_return
	Glb_CSNNA_Already_Schedule		flag

	Glb_Ntwk_Msg_Assert_Title		string
	Glb_Report_Title			string
}\
data Hierarchy_Data_Type {
	Retrieve_HM_RTDB_Step_Enum    enum {
		DH_Step_Get_Primary_Account_Inf,
		DH_Step_Get_Secondary_Account_Inf,
		DH_Step_Hierarchy_Search_Complete,
	}
	Hierarchy_Request_Result_Enum    enum {
		HR_Success,
		HR_Wrong_Hierarchy_Information,
		HR_HM_RTDB_Failure,
		HR_Invalid_Sponsoring_Account,	#V10.5 62977 
		HR_No_Sponsoring_MSISDN,	#V10.5 62977
		HR_No_Sponsoring_Account_eCS,	#V10.5 62977
	}
	# v10.12 65894
	Retrieve_GPRSSIM_Reason    enum {
		RGR_Master_Account,
		RGR_Sponsoring_Account,
		RGR_Normal_Account,	# V10SU13 66403
		RGR_IntraCOS_Account,	#VFGH 69452
		RGR_External_Query,	# SP27.7 Feauture 69716 VFGH
		RGR_Intra_Group,	# SP27.9 Feature 70577 VFCZ
		RGR_Index_Data_Sync_Update,	#72113
		RGR_Index_Data_Query,	#72113
		RGR_Index_Data_Query_Self_Learning,	#72113
		RGR_IDQ_Healing_Re02_Read_GPRSSIM,      #73254 ih_cr33608
		RGR_Query_Operation,	#72817
		RGR_Sync_Group_Host,	#76541
	}
	# SP28.5 72113
	RTDB_Op_Reason    enum {
		Reason_NULL,
		Sync_RTDB,
		Index_Data_Query,
		Index_Data_Query_Self_Learning,
		Index_Data_Query_Self_Healing_Return02_Read_ID2MDN,
		Index_Data_Query_Self_Healing_Return02_Del_GPRSSIM,
		Sync_Group_SCP,	#76541
	}

	#SP27.7 VFGH feature 69716
	Attach_Detach_RTDB_Next_Operation_Or_Source_Enum    enum {
		NULL					= 0,
		Next_CLIINFO_Replace			= 1,
		Next_CLIINFO_Insert			= 2,
		Next_Send_To_Ectrl			= 3,
		Source_From_Attach			= 4,
		Source_From_Detach			= 5,
	}
	# V10SU13 66403
	Account_ID_List_rec	record {
		Account_ID				string(24),
	}

	Account_ID_List_Table			table    Account_ID_List_rec

	Data_Request_Dataview_Status_Enum    enum {
		DR_P_Unavailable,
		DR_T_Unavailable,
		DR_Available,
	}

	LDAP_Link_Status_rec	record {
		Link_Instance				counter,
		Link_Status				Data_Request_Dataview_Status_Enum,
		Last_Attach_Time			counter,
		Attach_Inprog				flag,
		Retried_Times				counter,	#R28.5 72113
	}

	Glb_Inter_HOST_LDAP_Link_Table		hash table(string)    LDAP_Link_Status_rec
	Req_Idx_rec	record {
		OP					string,
		Action					string,
		Member_ID				string,
		LDAP_String				string,
	}

	LDAP_ReqData_Key_Field_rec	record {
		Key_Value				string,	# Value of name=value pair in LDAP Key
	}
	Update_GPRSSIM_rec	record {
		MDN					string,
		SCP_Name				string,
		IMSI1					string,
		COSP_ID					string,
		Provider_ID				string,
		State					string,
	}
	General_Call_From_Enum_Type    enum {
		GCF_None,
		GCF_Upd_Counter_Broadcast_Para,
	}
	General_Result_Code_Enum_Type    enum {
		GRC_None,
		GRC_Failed,
		GRC_Success,
		GRC_Query_With_Healing,
		GRC_Duplicated_Message,
		GRC_Not_Find, #_add_in_73582
		GRC_Busy, #SP28.10 feature 73939
	}
        #R28.7 73494 
        Learning_Healing_Enum_Type      enum {
                Self_Learning,
                Self_Healing,
        } 	
        LDAP_ReqData_Key_Table			hash table(string)    LDAP_ReqData_Key_Field_rec
	Attach_Inter_HOST_DR_Dataview_Type    def_event {}
	Attach_Inter_HOST_DR_Dataview_Result_Type    def_event {}

	#R28.5 72113
	String_Index_Table			hash table(string)    record {}
	# SP28.5 Vzw 72544 
	SCP_Info_rec	record {
		SCP_Name				string,
		Service_Type				counter,
		IMSI1					string,
		#SP28.7 VzW 73254
                E_IMSI1                                 string,
                E_IMSI2                                 string,
                UA                                      string,
	}

	#SP28.6 72000
	Account_List_Record	record {
		Account_List_tbl			Account_ID_List_Table,
	}

	Hierarchy_Structure_rec	record {
		present					flag,
		Account_List_rec			Account_List_Record,
		Level_Number				counter,
		Relation_Level				counter,
		BR_Level				counter,
		SCP_Name				string,
	}
	
	# SP28.14 75195
	Retrieve_CD_RTDB_Step_Enum enum {
		Req_Qry_Sec_Acc_Hier_Info,
		Req_Qry_Sec_Acc_Hier_Info_To_Top,
		Req_Primary_Group_Exist,
		Req_Qry_Hier_Info_For_Acct,
		Req_Group_Info,
		P_S_Req_Group_Info,
		P_S_Req_Group_Info_Online,
		P_S_Req_Group_Info_Online_To_Top,
		Upd_GPRSSIM_For_Online,		#76541
	}

}\
data Server_Meas_Type {
	Service_Measurement_Rec_Type	record {
		#MEAS 1
		Number_of_Successful_cDB_Accesses	counter,
		#MEAS 2
		Number_of_Unsuccessful_cDB_Accesses	counter,
		# SP28.7 72850
		# MEAS 3
		Successful_Local_Index_Query		counter,
		# MEAS 4
		Successful_SelfLearning_Attempt		counter,
		# MEAS 5
		Failed_SelfLearning_Attempt		counter,
		# MEAS 6
		Successful_SelfHealing_Attempt		counter,
		# MEAS 7
		Failed_SelfHealing_Attempt		counter,
		# MEAS 8
		Received_Insert_Via_Broadcast		counter,
		# MEAS 9
		Received_Delete_Via_Broadcast		counter,
		# MEAS 10
		Received_Update_Via_Broadcast		counter,
		# MEAS 11
		Failed_Insert_Due_Sub_Exist		counter,
		# MEAS 12
		Insert_Converted_To_Upd_Due_Datachg	counter,
		# SP28.10 73494
		# MEAS 13 Number of Timeout Self-Learning Attempt
		Timeout_Self_Learning_Attempts          counter,
		# MEAS 14 Number of Timeout Self-Healing Attempts
		Timeout_Self_Healing_Attempts           counter,
		# MEAS 15 Number of Suppressed Self-Learning for Previous Failure
		Suppressed_Self_Learning_For_Prev_F     counter,
		# SP28.10 72850
		# MEAS 16 
		UnSuccessful_GPRSSIM_Query		counter,
		#SP28.10 73939
		# MEAS 17 Number of LDAP Group Broadcast Request Filtered by Overload Control
		LDAP_GBrdC_Flt_By_OLC			counter,
		# MEAS 18 Number of LDAP Member Usage Report Filtered by Overload Control
		LDAP_MUsg_Flt_By_OLC                    counter,
		# MEAS 19 Number of LDAP Request About Index Server Filtered by Overload Control
		LDAP_IdxReq_Flt_By_OLC                  counter,
		# MEAS 20 Number of LDAP Request About Hierarchy Filtered by Overload Control
		LDAP_HierReq_Flt_By_OLC                 counter,
		#MEAS 21 Number of Other LDAP Request Filtered by Overload Control
		LDAP_OthReq_Flt_By_OLC                  counter,
		# SP28.7 IMR404522
		#V2807_EPPSM_SpareMea_61			counter,
		#V2807_EPPSM_SpareMea_62			counter,
		#V2807_EPPSM_SpareMea_63			counter,
		#V2807_EPPSM_SpareMea_64			counter,
		#V2807_EPPSM_SpareMea_65			counter,
		#V2807_EPPSM_SpareMea_66			counter,
		#V2807_EPPSM_SpareMea_67			counter,
		#V2807_EPPSM_SpareMea_68			counter,
		V2807_EPPSM_SpareMea_1			counter,
		V2807_EPPSM_SpareMea_2			counter,
		V2807_EPPSM_SpareMea_3			counter,
		V2807_EPPSM_SpareMea_4			counter,
		V2807_EPPSM_SpareMea_5			counter,
		V2807_EPPSM_SpareMea_6			counter,
		V2807_EPPSM_SpareMea_7			counter,
		V2807_EPPSM_SpareMea_8			counter,
		V2807_EPPSM_SpareMea_9			counter,
		V2807_EPPSM_SpareMea_10			counter,
		V2807_EPPSM_SpareMea_11			counter,
		V2807_EPPSM_SpareMea_12			counter,
		V2807_EPPSM_SpareMea_13			counter,
		V2807_EPPSM_SpareMea_14			counter,
		V2807_EPPSM_SpareMea_15			counter,
		V2807_EPPSM_SpareMea_16			counter,
		V2807_EPPSM_SpareMea_17			counter,
		V2807_EPPSM_SpareMea_18			counter,
		V2807_EPPSM_SpareMea_19			counter,
		V2807_EPPSM_SpareMea_20			counter,
		V2807_EPPSM_SpareMea_21			counter,
		V2807_EPPSM_SpareMea_22			counter,
		V2807_EPPSM_SpareMea_23			counter,
		V2807_EPPSM_SpareMea_24			counter,
		V2807_EPPSM_SpareMea_25			counter,
		V2807_EPPSM_SpareMea_26			counter,
		V2807_EPPSM_SpareMea_27			counter,
		V2807_EPPSM_SpareMea_28			counter,
		V2807_EPPSM_SpareMea_29			counter,
		V2807_EPPSM_SpareMea_30			counter,
		V2807_EPPSM_SpareMea_31			counter,
		V2807_EPPSM_SpareMea_32			counter,
		V2807_EPPSM_SpareMea_33			counter,
		V2807_EPPSM_SpareMea_34			counter,
		V2807_EPPSM_SpareMea_35			counter,
		V2807_EPPSM_SpareMea_36			counter,
		V2807_EPPSM_SpareMea_37			counter,
		V2807_EPPSM_SpareMea_38			counter,
		V2807_EPPSM_SpareMea_39			counter,
		V2807_EPPSM_SpareMea_40			counter,
		V2807_EPPSM_SpareMea_41			counter,
		V2807_EPPSM_SpareMea_42			counter,
		V2807_EPPSM_SpareMea_43			counter,
		V2807_EPPSM_SpareMea_44			counter,
		V2807_EPPSM_SpareMea_45			counter,
		V2807_EPPSM_SpareMea_46			counter,
		V2807_EPPSM_SpareMea_47			counter,
		V2807_EPPSM_SpareMea_48			counter,
		V2807_EPPSM_SpareMea_49			counter,
		V2807_EPPSM_SpareMea_50			counter,
		V2807_EPPSM_SpareMea_51			counter,
		V2807_EPPSM_SpareMea_52			counter,
		V2807_EPPSM_SpareMea_53			counter,
		V2807_EPPSM_SpareMea_54			counter,
		V2807_EPPSM_SpareMea_55			counter,
		V2807_EPPSM_SpareMea_56			counter,
		V2807_EPPSM_SpareMea_57			counter,
		V2807_EPPSM_SpareMea_58			counter,
		V2807_EPPSM_SpareMea_59			counter,
		V2807_EPPSM_SpareMea_60			counter,
	}

	Service_Measurement_Handling_Type    def_event {
		Content					Service_Measurement_Rec_Type,
	}
}
