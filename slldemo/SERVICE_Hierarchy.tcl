#---------------------------------------------------------------------------
# FILE
#               SERVICE_Hierarchy.tcl
#
# OWNER
#
#               dhj
# HISTORY
#
#               First release, 02/16/2004
#
# PURPOSE
#
#               Defines behaviors for EPPSM service administrator logics.
#
# DESCRIPTION
#               The following behaviors are defined in this file:
#		- SERVICE_ADMIN_Initialize
#		- Default_Event_Code:
#			HM_RTDB!read_completed
#			HM_RTDB!read_failed
#			P_S!Request_Hierarchy_Information
#			HM_RTDB_Retrieve
#			HM_Retrieve_Result
#			Service_Non_Fatal_Error
#			HM_Retrieve_Result_Primary_Account
#			HM_Retrieve_Result_Secondary_Account
#			Determine_Hierarchy_Complete
#			Get_Access_Index
#			RTDB_AttachFailed
#			Service_Terminate_Call
#
#---------------------------------------------------------------------------
component SERVICE_Hierarchy \
behavior SERVICE_ADMIN_Initialize {
	
	schedule( clock	= clock() + 10,
		  to = customer_index(),
		  event	= Get_Access_Index )
	#ih_cr31280
	set Glb_Check_GPRSSIM_Lock_Timer = 2
	set Glb_Retry_Check_Limit = 2

	#sp27.7 VFGH feature 69723
%%set SPA_NAME \"$env(SP)\"

	set Glb_SPA_NAME = ${SPA_NAME}
	set Glb_Internal_Operation_Assert_Title =
                        "REPT INTERNAL ASSERT=304, SPA=" : Glb_SPA_NAME

	# v10.12 65894
	set Glb_RTDB_Operation_Assert_Title =
                        "REPT INTERNAL ASSERT=305, SPA=EPPSM" 
	set Glb_DEBUG_LEVEL = 2
	
	# SP28.14 75195
	set Glb_RTDB_Data_Assert_Title = 
		"REPT MANUAL ASSERT=103, SPA=" : Glb_SPA_NAME

	set Glb_HM_RTDB_Table =	"HMRTDB"
	set Glb_Group_IDs_Max_Length = 3001	#Feature 70577
        set Glb_GSL_SCP_Name = host_name()

	# SP27.9 feature 70577
	set Glb_Service_Measurement_Interval = 2

	reset Glb_RTDB_Attach_Ret_Val

	#R27.7 Inter-spa commu & 3D tool test code
	set spi_protocol_handle = create_protocol_handle("spi",pp_hex_data) #may fail
	set spi_protocol_bound = spi_protocol_handle.handle
	
	# Attach to the	HM_RTDB	
	# Check	to see if we have already attached to the RTDB
	# If not, then initialize the RTDB
	if Glb_HM_RTDB_Instance	== 0
	then
		# Attach to the	HM RTDB	
		# from v10.12 65894, check mode in global rc
		test HM_RTDB_Mode	
		case 0
			# In Memory - Attached
			set Glb_RTDB_Attach_Ret_Val 
			    = HM_RTDB!attach(Glb_HM_RTDB_Table)	
			set Glb_HM_RTDB_In_Memory
		case 1
			# In Memory - Detached
			set Glb_RTDB_Attach_Ret_Val
			    = HM_RTDB!attach_no_cache(Glb_HM_RTDB_Table)
			reset Glb_HM_RTDB_In_Memory
		case 2
			# Disk Based
			set Glb_RTDB_Attach_Ret_Val =
			    HM_RTDB!attach(Glb_HM_RTDB_Table)
			reset Glb_HM_RTDB_In_Memory
		case 3
			# no used
			set Glb_RTDB_Attach_Ret_Val = e_no_error
			reset Glb_HM_RTDB_In_Memory
		other
			set Glb_RTDB_Attach_Ret_Val = e_no_error
			reset Glb_HM_RTDB_In_Memory
		end test
	
		if Glb_RTDB_Attach_Ret_Val == e_a_okay
		then
			set Glb_HM_RTDB_Instance =
			    HM_RTDB!get_instance(Glb_HM_RTDB_Table)
			if Glb_HM_RTDB_Instance	!= 0
			then
				# RTDB instance	is valid
				set Glb_HM_RTDB_Attached
			else
				# RTDB instance	is zero	- not a	valid
				# value	for an attached	RTDB
				reset Glb_HM_RTDB_Attached
				# Schedule a near immediate report
				# of this failure
				set RTDB_AttachFailed.RTDB_Name	
				    = Glb_HM_RTDB_Table	
				set RTDB_AttachFailed.Reason 
				    = "Get_instance Failed, Reason = ":
				    "Attached RTDB Instance is zero"
				schedule(event=RTDB_AttachFailed,
					clock=clock()+10)
			end if
 
		else
			# Failed to attach to the HM RTDB
			reset Glb_HM_RTDB_Attached
			# Schedule a near immediate report of this failure
			# ih_cr33830, skip send_om for RTDB Mode=3
			if Glb_RTDB_Attach_Ret_Val != e_no_error
			then
				set RTDB_AttachFailed.RTDB_Name	
			    		= Glb_HM_RTDB_Table	
				set RTDB_AttachFailed.Reason
			    		="Attach Failed.Reason=" 
			    		: string(Glb_RTDB_Attach_Ret_Val)
				schedule(event=RTDB_AttachFailed, clock=clock()+10)
			end if
		end if
	end if
	# SP27.9 feature 70577
	schedule( clock = clock() + 30,
		  to = customer_index(),
		  event = Request_Generate_Service_Measurement )
		  



}\
behavior Functions              {
#72544 Service Sensitive Routing
#-----------------------------------------------------------------------------
# Function:     Set_GPRSSIM_Info_For_Insert 
#
# Description:  This function is used to set GPRSSIM Key when need insert a re
#               cord in GPRSSIM RTDB during sync index data procedure.
#
#Parameter:
#       Input:
#       Output: flag
#
#-----------------------------------------------------------------------------
def_function Set_GPRSSIM_Info_For_Insert () flag
	reset GPRSSIM_Record1
	set GPRSSIM_Record1.MSISDN = GPRSSIM_Retrieve.Key_Index
	set GPRSSIM_Record1.Host_SCP_Name = Sync_Index_Data_Parameter_rec.SCP_Name
	set GPRSSIM_Record1.Life_Cycle_State = Sync_Index_Data_Parameter_rec.State
	set GPRSSIM_Record1.Provider_ID = Sync_Index_Data_Parameter_rec.Provider_ID
	set GPRSSIM_Record1.COSP_ID = Sync_Index_Data_Parameter_rec.COSP_ID
	if Number_Of_Collected_Index_Data > 1
	then
		if Sync_Index_Data_Parameter_rec.Is_ASCP
		then
			set GPRSSIM_Record1.Service_Type_1 = Sync_Index_Data_Parameter_rec.Service_Type
		end if
	end if

	return(true)
end def_function Set_GPRSSIM_Info_For_Insert

#--------------------------------------------------------------------------------------
#
#function:      Upd_SCP_For_Insert_Sync_Data
#
#Description:   This function is added in 72544 , when insert record into GPRSSIM
#               RTDB and this record has been existed, use this function to handle
#                update Host_SCP_Name and Aternative_SCP_Name.
#Parameter:
#       Input:
#       Output: flag
#
#-------------------------------------------------------------------------------------
def_function Upd_SCP_For_Insert_Sync_Data () flag
dynamic
	Local_Update_GPRSSIM_Flag		flag
end dynamic
	if Sync_Index_Data_Parameter_rec.Is_ASCP
	then
		if GPRSSIM_Record1.Host_SCP_Name != "" && GPRSSIM_Record1.Alternative_Host_SCP == ""
			&& GPRSSIM_Record1.Service_Type_1 == 1
		then
			if GPRSSIM_Record1.Host_SCP_Name != Sync_Index_Data_Parameter_rec.SCP_Name
			then
				set Local_Update_GPRSSIM_Flag
				set GPRSSIM_Record1.Host_SCP_Name = Sync_Index_Data_Parameter_rec.SCP_Name
				set GPRSSIM_Flag.Host_SCP_Name
			end if
		else
			if GPRSSIM_Record1.Alternative_Host_SCP != Sync_Index_Data_Parameter_rec.SCP_Name
			then
				set Local_Update_GPRSSIM_Flag
				set GPRSSIM_Record1.Alternative_Host_SCP = Sync_Index_Data_Parameter_rec.SCP_Name
				set GPRSSIM_Flag.Alternative_Host_SCP
			end if
			if GPRSSIM_Record1.Service_Type_1 != Sync_Index_Data_Parameter_rec.Service_Type
			then
				set Local_Update_GPRSSIM_Flag
				set GPRSSIM_Record1.Service_Type_1 = Sync_Index_Data_Parameter_rec.Service_Type
				set GPRSSIM_Flag.Service_Type_1
			end if
		end if
	else
		if GPRSSIM_Record1.Host_SCP_Name != Sync_Index_Data_Parameter_rec.SCP_Name
		then
			set Local_Update_GPRSSIM_Flag
			if GPRSSIM_Record1.Alternative_Host_SCP == "" && GPRSSIM_Record1.Service_Type_1 == 1 && GPRSSIM_Record1.Host_SCP_Name != ""
			then
				set GPRSSIM_Record1.Alternative_Host_SCP = GPRSSIM_Record1.Host_SCP_Name
				set GPRSSIM_Flag.Alternative_Host_SCP
			end if
			set GPRSSIM_Record1.Host_SCP_Name = Sync_Index_Data_Parameter_rec.SCP_Name
			set GPRSSIM_Flag.Host_SCP_Name
		end if
	end if

	#finally,check if ASCP is not null and Host SCP is null, move ASCP to HSCP
	if GPRSSIM_Record1.Host_SCP_Name == "" && GPRSSIM_Record1.Alternative_Host_SCP != ""
	then
		set Local_Update_GPRSSIM_Flag
		set GPRSSIM_Record1.Host_SCP_Name = GPRSSIM_Record1.Alternative_Host_SCP
		set GPRSSIM_Flag.Host_SCP_Name
		reset GPRSSIM_Record1.Alternative_Host_SCP
		set GPRSSIM_Flag.Alternative_Host_SCP
	end if

	return(Local_Update_GPRSSIM_Flag)
end def_function Upd_SCP_For_Insert_Sync_Data

#--------------------------------------------------------------------------------------
#
#function:      Upd_SCP_For_Del_Sync_Data 
#
#Description:   This function is added in 72544 , when delete record into GPRSSIM
#               RTDB and this record has been existed, use this function to handle
#                update Host_SCP_Name and Aternative_SCP_Name. 
#Parameter:
#       Input:
#       Output: Upd_SCP_For_RTDB_OP_Enum :RTDB operation type
#
#-------------------------------------------------------------------------------------
def_function Upd_SCP_For_Del_Sync_Data () Upd_SCP_For_RTDB_OP_Enum
dynamic
	Local_Upd_SCP_For_RTDB_OP		Upd_SCP_For_RTDB_OP_Enum
end dynamic

	if Sync_Index_Data_Parameter_rec.SCP_Name == GPRSSIM_Record1.Host_SCP_Name
	then
		if GPRSSIM_Record1.Alternative_Host_SCP != ""
		then
			set GPRSSIM_Record1.Host_SCP_Name = GPRSSIM_Record1.Alternative_Host_SCP
			reset GPRSSIM_Record1.Alternative_Host_SCP
			set GPRSSIM_Flag.Alternative_Host_SCP
			set GPRSSIM_Flag.Host_SCP_Name
			set Local_Upd_SCP_For_RTDB_OP = RTDB_Update
		else
			reset GPRSSIM_Record1.Host_SCP_Name
			set GPRSSIM_Flag.Host_SCP_Name
		end if
	elif Sync_Index_Data_Parameter_rec.SCP_Name == GPRSSIM_Record1.Alternative_Host_SCP
	then
		reset GPRSSIM_Record1.Alternative_Host_SCP
		set GPRSSIM_Flag.Alternative_Host_SCP
		reset GPRSSIM_Record1.Service_Type_1
		set GPRSSIM_Flag.Service_Type_1
		set Local_Upd_SCP_For_RTDB_OP = RTDB_Update
	end if

	if GPRSSIM_Record1.Host_SCP_Name == "" && GPRSSIM_Record1.Alternative_Host_SCP == ""
	then
		#delete this record
		set GPRSSIM_Delete.Key_Index = GPRSSIM_Retrieve.Key_Index
		set Local_Upd_SCP_For_RTDB_OP = RTDB_Delete
	end if

	return(Local_Upd_SCP_For_RTDB_OP)
end def_function Upd_SCP_For_Del_Sync_Data

#--------------------------------------------------------------------------------
#
#function:      Get_Next_State_For_Sync_Data
#
#Description:   This function is added in 72544 , used to get next state when sync
#               index data.
#            
#Parameter:
#       Input:
#       Output: Sync_RTDB_Step_Enum
#
#--------------------------------------------------------------------------------
def_function Get_Next_State_For_Sync_Data () Sync_RTDB_Step_Enum
	test Sync_Index_Data_Parameter_rec.OP
	case "0" # insert
		if Pre_Sync_RTDB_Step == Step_NULL
		then
			return(Insert_Insert_in_GPRSSIM_Step1)
		elif Pre_Sync_RTDB_Step == Insert_Insert_in_GPRSSIM_Step1
		then
			return(Insert_Insert_in_GPRSSIM_Step2)
		elif Pre_Sync_RTDB_Step == Insert_Insert_in_GPRSSIM_Step2
		then
			return(Insert_Insert_in_GPRSSIM_Step3)
		end if
	case "1" #delete
		if Pre_Sync_RTDB_Step == Step_NULL
		then
			return(Del_Delete_in_GPRSSIM_Step1)
		elif Pre_Sync_RTDB_Step == Del_Delete_in_GPRSSIM_Step1
		then
			return(Del_Delete_in_GPRSSIM_Step2)
		elif Pre_Sync_RTDB_Step == Del_Delete_in_GPRSSIM_Step2
		then
			return(Del_Delete_in_GPRSSIM_Step3)
		end if
	case any("2", "3")
		#76541
		if Online_Hierarchy && Request_Index_Service_Parameter_rec.ID_Type == "G"
		then
			return( Upd_For_Online_Hier_Step )
		else
			if Pre_Sync_RTDB_Step == Step_NULL
			then
				return(Update_OP2or3_Step1)
			elif Pre_Sync_RTDB_Step == Update_OP2or3_Step1
			then
				return(Update_OP2or3_Step2)
			elif Pre_Sync_RTDB_Step == Update_OP2or3_Step2
			then
				return(Update_OP2or3_Step3)
			elif Pre_Sync_RTDB_Step == Del_Delete_in_GPRSSIM_Step1
			then
				return(Del_Delete_in_GPRSSIM_Step2)
			elif Pre_Sync_RTDB_Step == Del_Delete_in_GPRSSIM_Step2
			then
				return(Del_Delete_in_GPRSSIM_Step3)
			end if

			#SP28.7 VzW 73254
			if Sync_Index_Data_Parameter_rec.OP == "3"
				&& Pre_Sync_RTDB_Step == Update_OP2or3_Step3
			then
				return(Update_OP2or3_Step4)
			end if
		end if

	end test
	return(Step_NULL)
end def_function Get_Next_State_For_Sync_Data

#--------------------------------------------------------------------------------
#
#function:  Set_Info_Before_Read_GPRSSIM    
#
#Description:   This function is added in 72544 ,  used to set GPRSSIM retrieve key
#               and sync step before Retrieve GPRSSIM RTDB.
#                
#Parameter:
#       Input:  Input_Pre_Sync_Step     Sync_RTDB_Step_Enum
#               Input_Key_Index         string
#
#       Output: flag
#
#--------------------------------------------------------------------------------
def_function Set_Info_Before_Read_GPRSSIM (
		Input_Pre_Sync_Step			Sync_RTDB_Step_Enum,
		Input_Key_Index				string
	) flag
	set Pre_Sync_RTDB_Step = Input_Pre_Sync_Step
	set GPRSSIM_Retrieve.Key_Index = Input_Key_Index
	set Retrieve_GPRSSIM_For = RGR_Index_Data_Sync_Update

	test Sync_Index_Data_Parameter_rec.OP
	case "0"
		set Sync_RTDB_Step = Insert_GPRSSIM_Retrieve_Step
	case "1"
		set Sync_RTDB_Step = Del_GPRSSIM_Retrieve_Step
	case any("2", "3")
		if Pre_Sync_RTDB_Step == any(Del_Delete_in_GPRSSIM_Step1, Del_Delete_in_GPRSSIM_Step2)
		then
			set Sync_RTDB_Step = Del_GPRSSIM_Retrieve_Step
		else
			set Sync_RTDB_Step = Update_GPRSSIM_Retrieve_Step
		end if
	end test

	return(true)
end def_function Set_Info_Before_Read_GPRSSIM
def_function Incr_Data_Request_Completed_Counter(In_Result_Code string) flag
	if In_Result_Code == "00"
	then
		incr Data_Req_Rec_Suc_00_Msg_Num
		if Data_Req_To_Des_Flag
		then
			test Member_Group_ID_Type
			case "S"
				incr Data_Req_Rec_Suc_00_Msg_Num_Broadcast
			case "G"
				incr Data_Req_Rec_Suc_00_Msg_Num_U_Or_Q
			end test
		end if
	elif In_Result_Code == "02"
	then
		incr Data_Req_Rec_Suc_02_Msg_Num
		if Data_Req_To_Des_Flag
		then
			test Member_Group_ID_Type
			case "S"
				incr Data_Req_Rec_Suc_02_Msg_Num_Broadcast
			case "G"
				incr Data_Req_Rec_Suc_02_Msg_Num_U_Or_Q
			end test
		end if
	elif In_Result_Code == "03"
	then
		incr Data_Req_Rec_Suc_03_Msg_Num
		if Data_Req_To_Des_Flag
		then
			test Member_Group_ID_Type
			case "S"
				incr Data_Req_Rec_Suc_03_Msg_Num_Broadcast
			case "G"
				incr Data_Req_Rec_Suc_03_Msg_Num_U_Or_Q
			end test
		end if
	else
		incr Data_Req_Rec_Suc_Oth_Msg_Num
		if Data_Req_To_Des_Flag
		then
			test Member_Group_ID_Type
			case "S"
				incr Data_Req_Rec_Suc_Oth_Msg_Num_Broadcast
			case "G"
				incr Data_Req_Rec_Suc_Oth_Msg_Num_U_Or_Q
			end test
		end if
	end if
	reset Data_Req_To_Des_Flag
	return (true)
end def_function Incr_Data_Request_Completed_Counter

def_function Whh_Test () flag
	return (true)
end def_function Whh_Test

#--------------------------------------------------------------------------------
#
#function:  Set_Info_Before_Read_ID2MDN
#
#Description:   This function is added in 73254 ,  used to set ID2MDN retrieve key
#               and sync step before Retrieve ID2MDN RTDB.
#                
#Parameter:
#       Input:  Input_Pre_Sync_Step     Sync_RTDB_Step_Enum
#               Input_Key_Index         string
#
#       Output: flag
#
#--------------------------------------------------------------------------------
def_function Set_Info_Before_Read_ID2MDN (
		Input_Pre_Sync_Step			Sync_RTDB_Step_Enum,
		Input_Key_Index				string
	) flag

	set Pre_Sync_RTDB_Step = Input_Pre_Sync_Step
	set ID2MDN_RTDB_Retrieve.Key_Index = Input_Key_Index
	set RTDB_Op_For = Sync_RTDB

	test Sync_Index_Data_Parameter_rec.OP
	case "0"
		set Sync_RTDB_Step = Insert_ID2MDN_RTDB_Retrieve_Step
	case "1"
		set Sync_RTDB_Step = Del_ID2MDN_RTDB_Retrieve_Step
	case any("2", "3")
		if Pre_Sync_RTDB_Step == any(Del_Delete_in_GPRSSIM_Step1, Del_Delete_in_GPRSSIM_Step2, Del_Delete_in_GPRSSIM_Step3)
		then
			set Sync_RTDB_Step = Del_ID2MDN_RTDB_Retrieve_Step
		else
			set Sync_RTDB_Step = Insert_ID2MDN_RTDB_Retrieve_Step
		end if
	end test

	return(true)
end def_function Set_Info_Before_Read_ID2MDN

#-------------------------------------------------------------------------
#Function:      Account_ID_Mapping
#
#Description:   This function is added in 73178 for key mapping by jinchaol.
#               Search Enhanced Parameter Mapping_tbl to get new Account_ID
#
#Parameter:
#       Input:  Input_Value
#               Old_Account_ID
#       Output: New_Account after keymapping logic
#-------------------------------------------------------------------------
def_function Account_ID_Mapping (
		Input_Value				string,
		Old_Account_ID				string
	) string
dynamic
	Local_EPM_Key				EPM_Key_Type
	Local_New_Account_ID			string
	Local_Start_End_Pos			string
	Local_Start_Pos				counter
	Local_String_1				string
end dynamic

	set Local_New_Account_ID = Old_Account_ID # if no mapping found, use Old_Account_ID
	if(Old_Account_ID == " " || Input_Value != any("Condense", "Expansion"))
	then
		return(Local_New_Account_ID)
	end if

	set Local_EPM_Key.Key_String_1 = Input_Value : ":Digit_Position:ALL:ALL"
	set Local_EPM_Key.Key_String_2 = "ALL:ALL"
	set Local_EPM_Key.Mapping_Parameter_6 = "ALL"
	set Local_EPM_Key.Mapping_Parameter_7 = "ALL"
	set Local_EPM_Key.Mapping_Parameter_8 = "ALL"

	if element_exists(Enhanced_Parameter_Mapping_tbl, Local_EPM_Key)
	then
		set Local_Start_End_Pos = Enhanced_Parameter_Mapping_tbl[Local_EPM_Key].Output_Value
		Parse_Object(":", Local_Start_End_Pos)

		# error handling of "start:end": "", ":2", "23", "a:", "2:3:b", "a:b", "3:2",
		# "-2:-3", "2a:3b", "0:3", "1000:1001", etc
		if Glb_Parsed == "" || Glb_Remainder == ""
			|| (counter(Glb_Remainder) < counter(Glb_Parsed))
			|| (counter(Glb_Parsed) < 1)
			|| map(Glb_Parsed, "0123456789", "") != ""
			|| map(Glb_Remainder, "0123456789", "") != ""
			|| (counter(Glb_Parsed) > length(Old_Account_ID))
		then
			return(Local_New_Account_ID)
		end if

		set Local_Start_Pos = counter(Glb_Parsed)
		set Local_String_1 = substring(Old_Account_ID, Local_Start_Pos, (counter(Glb_Remainder) - Local_Start_Pos + 1
			))

		#the second record
		set Local_EPM_Key.Key_String_1 = Input_Value : ":" : Local_String_1 : ":ALL:ALL"

		if element_exists(Enhanced_Parameter_Mapping_tbl, Local_EPM_Key)
		then
			set Local_String_1 = Enhanced_Parameter_Mapping_tbl[Local_EPM_Key].Output_Value
			set Local_String_1 = substring(Old_Account_ID, 1, Local_Start_Pos - 1) : Local_String_1
			set Local_New_Account_ID = Local_String_1 : substring(Old_Account_ID, (counter(Glb_Remainder) + 1), (
			length(Old_Account_ID) - counter(Glb_Remainder)))
		end if
	end if
	return(Local_New_Account_ID)
end def_function Account_ID_Mapping

#-------------------------------------------------------------------------
#Function:      Check_Account_ID_Map_Method
#
#Description:   This function is added in 73178 for check CP.Account_ID_Keymap
#
#Parameter:
#       Input:  Input_String
#       Output: New_Account after keymapping logic
#-------------------------------------------------------------------------
def_function Check_Account_ID_Map_Method (
		Input_String				string
	) string
dynamic
	Local_Mapping_Result_String		string
	Local_Check_Flag			flag
end dynamic

	if(!Hierarchy_Keymap_flag) ||
		(Hierarchy_Keymap_flag && find("-", Input_String) != 0)
	then
		# only Hierarchy_Keymap_flag  && doesn't contains '-' reset Hierarchy_Keymap_flag	
		set Local_Check_Flag
	end if

	if Account_Id_Keymap_Plan == Map_To_16_Length && length(Input_String) > 16
	then
		set Local_Mapping_Result_String = Account_ID_Mapping("Condense", Input_String)
	elif Local_Check_Flag && Account_Id_Keymap_Plan == Map_To_20_Length && length(Input_String) <= 16
	then
		set Local_Mapping_Result_String = Account_ID_Mapping("Expansion", Input_String)
	else
		set Local_Mapping_Result_String = Input_String
	end if
	return(Local_Mapping_Result_String)

end def_function Check_Account_ID_Map_Method

}\
behavior Default_Event_Code	{

#------------------------------------------------------------------------------	
# Event:	HM_RTDB!read_completed
#
# Description:	This event handler is executed when the	retrieve of the	RTDB
#		     HM_RTDB has completed DR_Successfully. The	retrieved
#		record will be copied to the record specified in the
#		     HM_RTDB_Record1 parameter.	
#------------------------------------------------------------------------------	
event HM_RTDB!read_completed
	set HM_RTDB_Record1 = @.data
	set HM_Retrieve_Result.success
	reset HM_Retrieve_Result.tuple_not_found
	next event HM_Retrieve_Result
	return
end event HM_RTDB!read_completed

#-------------------------------------------------------------------------------
# Event:	HM_RTDB!read_failed
#
# Description:	This event handler is executed when the	retrieve of the	RTDB
#		     HM_RTDB has failed.
#-------------------------------------------------------------------------------
event HM_RTDB!read_failed
	reset HM_Retrieve_Result
	if(@.failure_reason) != e_tuple_not_found
	then
		send_om(
	                msg_id = counter("30" : "305"),  #SP28.16 RDAF729606
			msg_class = GSL_Internal_Assert_Message_Class,
			poa = GSL_Internal_Assert_Priority,
			title = "REPT INTERNAL ASSERT=305, SPA=EPPSM",
			message = "Intenal System Error - RTDB operation failed, RTDB Name = " : Glb_HM_RTDB_Table : ".",
			message2 =
			"\nSubscriber ID = " :
			"\nCall Instance ID = " : string(call_index()) :
			"\nScenario Location = HM_RTDB!read_failed" :
			"\nFailure Reason=" : string(@.failure_reason) :
			"\nKey_Index Value=" : HM_RTDB_Key
			)
		reset HM_Retrieve_Result.tuple_not_found
	else
		set HM_Retrieve_Result.tuple_not_found
	end if

	reset HM_Retrieve_Result.success
	next event HM_Retrieve_Result
	return
end event HM_RTDB!read_failed
#------------------------------------------------------------------------------ 
# Event:        GPRSSIM_Retrieve_Result
#
# Description:  
#
#------------------------------------------------------------------------------ 
event GPRSSIM_Retrieve_Result
        #R28.10 73494
        if @.success
        then
               incr Glb_Service_Measurement_Rec.Successful_Local_Index_Query
        else
               incr Glb_Service_Measurement_Rec.UnSuccessful_GPRSSIM_Query
        end if  
        # v10.12 65894
	test Retrieve_GPRSSIM_For
	case RGR_Master_Account
		if @.success
		then
			set Master_Account_eCS_Name = GPRSSIM_Record1.Host_SCP_Name
		end if

		if Sponsoring_Account_ID != ""
		then
			set Retrieve_GPRSSIM_For = RGR_Sponsoring_Account
			set GPRSSIM_Retrieve.Key_Index = Sponsoring_Account_ID
			next event GPRSSIM_Retrieve
			return
		end if
	case RGR_Sponsoring_Account
		if @.success
		then
			set Sponsoring_Account_eCS_Name = GPRSSIM_Record1.Host_SCP_Name
		end if
		reset Retrieve_GPRSSIM_For
	case RGR_Normal_Account
		if @.success || @.tuple_not_found
		then
			# for tuple_not_found, GPRSSIM_Record1 is null
			if Account_ID_Pos == 1
			then
				set Master_Account_eCS_Name = GPRSSIM_Record1.Host_SCP_Name
			elif Account_ID_Pos == 2
			then
				set Sponsoring_Account_eCS_Name = GPRSSIM_Record1.Host_SCP_Name
			else
				set Account_SCP_List = Account_SCP_List : GPRSSIM_Record1.Host_SCP_Name : ","
			end if
			incr Account_ID_Pos
			next event Request_Query_Index_DB
			return
		else
			set Return_Result = HR_HM_RTDB_Failure
			next event Determine_Hierarchy_Complete_1
			return
		end if
	case RGR_IntraCOS_Account #VFGH Feature 69452
		if @.success
		then
			set Master_Account_eCS_Name = GPRSSIM_Record1.COSP_ID
		else
			reset Master_Account_eCS_Name
		end if
		reset Intra_Hierarchy_Flag
		next event Determine_Hierarchy_Complete_1
		return
	case RGR_External_Query

		reset Message_For_Ectrl_EPPSM_Rec
		set Message_Name_For_InterSPA = "GPRSSIMRtr"

		if @.success
		then
			set Message_For_Ectrl_EPPSM_Rec.cosp_id = GPRSSIM_Record1.COSP_ID
			set Message_For_Ectrl_EPPSM_Rec.host_name = GPRSSIM_Record1.Host_SCP_Name
			set Message_For_Ectrl_EPPSM_Rec.result_code = "success"
		elif @.tuple_not_found
		then
			set Message_For_Ectrl_EPPSM_Rec.result_code = "tuple_not_found"
		else
			set Message_For_Ectrl_EPPSM_Rec.result_code = "error"
		end if

		next event Send_Info_Back_To_ECTRL
		return
		#SP27.9 VFCZ 70577
	case RGR_Intra_Group
		if @.success || @.tuple_not_found || (Online_Hierarchy_Flag
			&& Query_Group_Operation == any("0", "2") && GLB_GPRSSIM_Not_Used)
		then
			# SP28.6 72000
			if Online_Hierarchy_Flag &&
				Query_Group_Operation == any("0", "2")
			then
				if GLB_GPRSSIM_Not_Used || GPRSSIM_Record1.Host_SCP_Name == ""
				then
					set Hierarchy_Structure_tbl.SCP_Name = Default_Group_SCP_Name
				else
					set Hierarchy_Structure_tbl.SCP_Name = GPRSSIM_Record1.Host_SCP_Name
				end if
				incr Account_ID_Pos
				next event Request_Query_Hier_Info_Continue
				return
			else

				# for tuple_not_found, GPRSSIM_Record1 is null
				set Account_SCP_List = Account_SCP_List : GPRSSIM_Record1.Host_SCP_Name : ","
				incr Account_ID_Pos
				next event Request_Query_Group_Info
				return
			end if
		else
			set Return_Result = HR_HM_RTDB_Failure
			next event Determine_Hierarchy_Complete_1
			return
		end if
		# SP28.5 72113 wenbiazh
	case RGR_Index_Data_Query
		if @.success
		then
			#ih_cr31419
			if GPRSSIM_Record1.Host_SCP_Name != "" || Number_Of_Collected_Index_Data > 1 && GPRSSIM_Record1.Alternative_Host_SCP != ""
			then
				reset Send_Request_Index_Service_Response
				set Send_Request_Index_Service_Response.resultcode = "00"
				set Send_Request_Index_Service_Response.MDN = GPRSSIM_Record1.MSISDN
				set Send_Request_Index_Service_Response.SCP_Name = GPRSSIM_Record1.Host_SCP_Name
				set Send_Request_Index_Service_Response.COSP_ID = GPRSSIM_Record1.COSP_ID
				set Send_Request_Index_Service_Response.Provider_ID = GPRSSIM_Record1.Provider_ID
				set Send_Request_Index_Service_Response.State = GPRSSIM_Record1.Life_Cycle_State
				# SP28.5 Vzw 72544
				set Send_Request_Index_Service_Response.Alternative_SCP = GPRSSIM_Record1.Alternative_Host_SCP
				set Send_Request_Index_Service_Response.Service_Type = GPRSSIM_Record1.Service_Type_1
				set Send_Request_Index_Service_Response.TP = GPRSSIM_Record1.Tariff_Plan
				if Request_Index_Service_Parameter_rec.ID_Type == "N"
				then
					set Send_Request_Index_Service_Response.IMSI1 = Request_Index_Service_Parameter_rec.ID
					#SP28.7 VzW 73254
				elif Request_Index_Service_Parameter_rec.ID != GPRSSIM_Record1.MSISDN
				then
					set Send_Request_Index_Service_Response.UA = Request_Index_Service_Parameter_rec.ID
				end if
				next event Send_Request_Index_Service_Response
				return
			else
				reset Send_Request_Index_Service_Response
				set Send_Request_Index_Service_Response.resultcode = "02"
				next event Send_Request_Index_Service_Response
				return
			end if
		elif @.tuple_not_found
		then
			#SP28.7 VzW 73254
			if First_GPRSSIM_Read && !GLB_ID2MDN_RTDB_Not_Used
			then
				reset First_GPRSSIM_Read
				set RTDB_Op_For = Index_Data_Query
				set ID2MDN_RTDB_Retrieve.Key_Index =
					Request_Index_Service_Parameter_rec.ID
				next event ID2MDN_RTDB_Retrieve
				return
			end if

			reset Send_Request_Index_Service_Response
			set Send_Request_Index_Service_Response.resultcode = "02"
			next event Send_Request_Index_Service_Response
			return
		else
			reset Send_Request_Index_Service_Response
			set Send_Request_Index_Service_Response.resultcode = "99"
			next event Send_Request_Index_Service_Response
			return
		end if
		# SP28.5 72113 wenbiazh
	case RGR_Index_Data_Query_Self_Learning
		if @.success && (GPRSSIM_Record1.Host_SCP_Name != "" || Number_Of_Collected_Index_Data > 1 && GPRSSIM_Record1.Alternative_Host_SCP != "")#ih_cr31419
		then
			if Upd_Counter_Broadcast_Flag #VzW Feature 72139
			then
				set Member_SCP_Name = GPRSSIM_Record1.Host_SCP_Name
				next event Upd_Counter_Bro_Para
				return
			end if
			reset Send_Request_Index_Service_Response
			set Send_Request_Index_Service_Response.resultcode = "00"
			set Send_Request_Index_Service_Response.MDN = GPRSSIM_Record1.MSISDN
			set Send_Request_Index_Service_Response.SCP_Name = GPRSSIM_Record1.Host_SCP_Name
			set Send_Request_Index_Service_Response.COSP_ID = GPRSSIM_Record1.COSP_ID
			set Send_Request_Index_Service_Response.Provider_ID = GPRSSIM_Record1.Provider_ID
			set Send_Request_Index_Service_Response.State = GPRSSIM_Record1.Life_Cycle_State
			# SP28.5 Vzw 72544
			set Send_Request_Index_Service_Response.Alternative_SCP = GPRSSIM_Record1.Alternative_Host_SCP
			set Send_Request_Index_Service_Response.Service_Type = GPRSSIM_Record1.Service_Type_1
			set Send_Request_Index_Service_Response.TP = GPRSSIM_Record1.Tariff_Plan
			if Request_Index_Service_Parameter_rec.ID_Type == "N"
			then
				set Send_Request_Index_Service_Response.IMSI1 = Request_Index_Service_Parameter_rec.ID
				#SP28.7 VzW 73254
			elif Request_Index_Service_Parameter_rec.ID != GPRSSIM_Record1.MSISDN
			then
				set Send_Request_Index_Service_Response.UA = Request_Index_Service_Parameter_rec.ID
			end if
			next event Send_Request_Index_Service_Response
			return
		else
			#SP28.7 VzW 73254
			if @.tuple_not_found && First_GPRSSIM_Read && !GLB_ID2MDN_RTDB_Not_Used
			then
				reset First_GPRSSIM_Read
				set RTDB_Op_For = Index_Data_Query_Self_Learning
				set ID2MDN_RTDB_Retrieve.Key_Index =
					Request_Index_Service_Parameter_rec.ID
				next event ID2MDN_RTDB_Retrieve
				return
			end if

			if Glb_IDX_QRY_FSM_Customer_Index == 0
			then
				if Upd_Counter_Broadcast_Flag #VzW Feature 72139
				then
					set Send_Upd_Counter_Bro_Para_Res.Result_Code = "99"
					next event Send_Upd_Counter_Bro_Para_Res
					return
				else
					reset Send_Request_Index_Service_Response
					set Send_Request_Index_Service_Response.resultcode = "99"
					next event Send_Request_Index_Service_Response
					return
				end if
			end if
			set Request_Self_Learning_Healing.Customer_Call_ID = call_index()
			if Upd_Counter_Broadcast_Flag #VzW Feature 72139
			then
				set Request_Self_Learning_Healing.ID = Member_Group_ID
				set Request_Self_Learning_Healing.ID_Type = Member_Group_ID_Type
			else
				set Request_Self_Learning_Healing.ID = Request_Index_Service_Parameter_rec.ID
				set Request_Self_Learning_Healing.ID_Type = Request_Index_Service_Parameter_rec.ID_Type
			end if
		        set Request_Self_Learning_Healing.Learning_Healing_Type = Self_Learning	
                        #R28.10 73494 
                        if Self_Learning_Blocked_List_Interval > 0 
                        then
                                set SLTBL_RTDB_Retrieve_Flag 
                                set SLTBL_RTDB_Retrieve.Key_Index = Request_Self_Learning_Healing.ID 
                                next event SLTBL_RTDB_Retrieve
                                return 
                        end if 	
                        set Req_SA_To_IQRY_Sending_Flag
			send(to = Glb_IDX_QRY_FSM_Customer_Index,
				event = Request_Self_Learning_Healing,
				ack = true)
			return
		end if
		# SP28.5 72113 wenbiazh
	case RGR_Index_Data_Sync_Update
		reset Retrieve_GPRSSIM_For
		set Sync_Index_Data_Parameter_rec.success = @.success
		set Sync_Index_Data_Parameter_rec.tuple_not_found = @.tuple_not_found
		next event Sync_Index_Data_With_OCS
		return
		#73254 ih_cr33608
	case RGR_IDQ_Healing_Re02_Read_GPRSSIM
		reset RTDB_Op_For
		set GPRSSIM_Delete.Key_Index = GPRSSIM_Retrieve.Key_Index
		next event GPRSSIM_Delete
		return
	case RGR_Query_Operation
		if @.success
		then
			set Sponsoring_Account_eCS_Name = GPRSSIM_Record1.Host_SCP_Name
		end if
		reset Retrieve_GPRSSIM_For
		next event Request_Query_Hier_Info
		return
	#76541
	case RGR_Sync_Group_Host
		if @.success
		then
			if GPRSSIM_Record1.Host_SCP_Name != Sync_Index_Data_Parameter_rec.SCP_Name
			then
				set GPRSSIM_Record1.Host_SCP_Name = Sync_Index_Data_Parameter_rec.SCP_Name
				set GPRSSIM_Flag.Host_SCP_Name
				set RTDB_Op_For = Sync_Group_SCP
				next event GPRSSIM_Replace
				return
			end if
		elif @.tuple_not_found
		then
			reset GPRSSIM_Record1
			set GPRSSIM_Record1.MSISDN = GPRSSIM_Retrieve.Key_Index
			set GPRSSIM_Record1.Host_SCP_Name = Sync_Index_Data_Parameter_rec.SCP_Name
			set RTDB_Op_For = Sync_Group_SCP
			next event GPRSSIM_Insert
			return
		end if
		incr Account_ID_Pos
		next event Upd_GPRSSIM_For_Online_Hier
		return
	end test
	next event Determine_Hierarchy_Complete_1
	return

end event GPRSSIM_Retrieve_Result
#R28.7 73494
event SLTBL_RTDB_Retrieve_Result
dynamic
    Local_Blocked_List_Interval counter  
end dynamic
         set Counter_Current_Clock = clock() 
         if SLTBL_RTDB_Retrieve_For_SelfH
         then
              set SLTBL_RTDB_Record1.Self_Learning_Failure_Timestamp = Counter_Current_Clock
              set SLTBL_RTDB_Updated_Flag 
              if @.success && SLTBL_RTDB_Record1.Account_ID != ""
              then
                   set SLTBL_Record_Found 
                   set SLTBL_RTDB_Flag.Self_Learning_Failure_Timestamp
                   next event SLTBL_RTDB_Replace
                   return
             else
                   if Upd_Counter_Broadcast_Flag
                   then
                            set SLTBL_RTDB_Record1.Account_ID = Member_Group_ID
                   else
                            set SLTBL_RTDB_Record1.Account_ID = Request_Index_Service_Parameter_rec.ID
                   end if
                   next event SLTBL_RTDB_Insert
                   return  
             end if
         end if 
         if @.success && SLTBL_RTDB_Record1.Account_ID != ""
         then
             set SLTBL_Record_Found
             set Local_Blocked_List_Interval = Self_Learning_Blocked_List_Interval 
             if SLTBL_RTDB_Record1.Self_Learning_Failure_Timestamp + 60 * Local_Blocked_List_Interval 
                   > Counter_Current_Clock
                      
             then
                   incr Glb_Service_Measurement_Rec.Suppressed_Self_Learning_For_Prev_F
                   reset Request_Index_Service_Result 
                   set Suppressed_SelfL_For_PreFaild_flag 
                   set Request_Index_Service_Result.Result_Code = "02" 
                   set Request_Index_Service_Result.MDN = SLTBL_RTDB_Record1.Account_ID 
                   next event Request_Index_Service_Result 
                   return 
             end if
             
        end if
        set Req_SA_To_IQRY_Sending_Flag
        send(to = Glb_IDX_QRY_FSM_Customer_Index,
                  event = Request_Self_Learning_Healing,
                     ack = true)
        return 
end event SLTBL_RTDB_Retrieve_Result
# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------ 
event GPRSSIM_Insert_Result
        #R28.10 73494 
        if @.success && Index_Data_Sync_Flag
        then
              incr Glb_Service_Measurement_Rec.Received_Insert_Via_Broadcast
        end if
        if Index_Data_Sync_Flag && @.duplicate_key
        then
              incr Glb_Service_Measurement_Rec.Failed_Insert_Due_Sub_Exist
        end if  	
        test RTDB_Op_For
	case Sync_RTDB
		reset RTDB_Op_For
		if Dup_Insert_Still_Update && @.duplicate_key
		then
			set Sync_RTDB_Step = Update_GPRSSIM_Retrieve_Step
			reset Dup_Insert_Still_Update
			set GPRSSIM_Retrieve.Key_Index = GPRSSIM_Record1.MSISDN
			set Retrieve_GPRSSIM_For = RGR_Index_Data_Sync_Update
			next event GPRSSIM_Retrieve
			return
		end if
		reset Dup_Insert_Still_Update
		next event Sync_Index_Data_With_OCS
		return
	#76541
	case Sync_Group_SCP
		reset RTDB_Op_For
		incr Account_ID_Pos
		next event Upd_GPRSSIM_For_Online_Hier
		return
	other
		next event Service_Terminate_Call
		return
	end test
end event GPRSSIM_Insert_Result

# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------ 
event GPRSSIM_Delete_Result
        #R28.10 73494 
        if @.success && Index_Data_Sync_Flag
        then
              incr Glb_Service_Measurement_Rec.Received_Delete_Via_Broadcast
        end if	
        test RTDB_Op_For
	case Sync_RTDB
		reset RTDB_Op_For
		next event Sync_Index_Data_With_OCS
		return
	other
		next event Service_Terminate_Call
		return
	end test
end event GPRSSIM_Delete_Result

# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------ 
event GPRSSIM_Replace_Result
        #R28.10 73494
        if @.success && Index_Data_Sync_Flag
        then
               if Index_Data_Sync_Insert_Flag
               then 
                   incr Glb_Service_Measurement_Rec.Insert_Converted_To_Upd_Due_Datachg 
               else
                   incr Glb_Service_Measurement_Rec.Received_Update_Via_Broadcast  
               end if 
        end if		
        test RTDB_Op_For
	case Sync_RTDB
		reset RTDB_Op_For
		next event Sync_Index_Data_With_OCS
		return
	case Sync_Group_SCP	#76541
		reset RTDB_Op_For
		incr Account_ID_Pos
		next event Upd_GPRSSIM_For_Online_Hier
		return
	other
		next event Service_Terminate_Call
		return
	end test
end event GPRSSIM_Replace_Result
#R28.7 73494
event SLTBL_RTDB_Delete_Result      
       next event Request_Index_Service_Result
       return
end event SLTBL_RTDB_Delete_Result 

event SLTBL_RTDB_Replace_Result      
       if @.tuple_not_found
       then
             next event SLTBL_RTDB_Insert
             return
       end if 
       next event Request_Index_Service_Result
       return
end event SLTBL_RTDB_Replace_Result

event SLTBL_RTDB_Insert_Result  
    if  @.duplicate_key
    then
	     set SLTBL_RTDB_Flag.Self_Learning_Failure_Timestamp                                        
             next event SLTBL_RTDB_Replace
	     return
    end if    
    next event Request_Index_Service_Result

end event SLTBL_RTDB_Insert_Result
# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------ 
event ID2MDN_RTDB_Retrieve_Result
	test RTDB_Op_For
	case Sync_RTDB
		reset RTDB_Op_For
		set Sync_Index_Data_Parameter_rec.success = @.success
		set Sync_Index_Data_Parameter_rec.tuple_not_found = @.tuple_not_found
		next event Sync_Index_Data_With_OCS
		return
	case Index_Data_Query
		if @.success
		then
			if ID2MDN_RTDB_Record1.MDN == ""
			then
				reset Send_Request_Index_Service_Response
				set Send_Request_Index_Service_Response.resultcode = "02"
				next event Send_Request_Index_Service_Response
				return
			else
				set Retrieve_GPRSSIM_For = RGR_Index_Data_Query
				set GPRSSIM_Retrieve.Key_Index = ID2MDN_RTDB_Record1.MDN
				next event GPRSSIM_Retrieve
				return
			end if
		elif @.tuple_not_found
		then
			#73254
			if Request_Index_Service_Parameter_rec.Ind == "Y"
			then
				set Retrieve_GPRSSIM_For = RGR_Index_Data_Query
				set GPRSSIM_Retrieve.Key_Index =
					Request_Index_Service_Parameter_rec.ID
				next event GPRSSIM_Retrieve
				return
			end if

			reset Send_Request_Index_Service_Response
			set Send_Request_Index_Service_Response.resultcode = "02"
			next event Send_Request_Index_Service_Response
			return
		else
			reset Send_Request_Index_Service_Response
			set Send_Request_Index_Service_Response.resultcode = "99"
			next event Send_Request_Index_Service_Response
			return
		end if
	case Index_Data_Query_Self_Learning
		if @.success && ID2MDN_RTDB_Record1.MDN != ""
		then
			set Retrieve_GPRSSIM_For = RGR_Index_Data_Query_Self_Learning
			set GPRSSIM_Retrieve.Key_Index = ID2MDN_RTDB_Record1.MDN
			next event GPRSSIM_Retrieve
			return
		else
			#SP28.7 VzW 73254
			if @.tuple_not_found && Request_Index_Service_Parameter_rec.Ind == "Y"
			then
				set Retrieve_GPRSSIM_For = RGR_Index_Data_Query_Self_Learning
				set GPRSSIM_Retrieve.Key_Index = Request_Index_Service_Parameter_rec.ID
				next event GPRSSIM_Retrieve
				return
			end if

			if Glb_IDX_QRY_FSM_Customer_Index == 0
			then
				reset Send_Request_Index_Service_Response
				set Send_Request_Index_Service_Response.resultcode = "99"
				next event Send_Request_Index_Service_Response
				return
			end if
			set Request_Self_Learning_Healing.Customer_Call_ID = call_index()
			set Request_Self_Learning_Healing.ID = Request_Index_Service_Parameter_rec.ID
			set Request_Self_Learning_Healing.ID_Type = Request_Index_Service_Parameter_rec.ID_Type
		        #R28.10 73494 
                        set Request_Self_Learning_Healing.Learning_Healing_Type = Self_Learning	
                        if Self_Learning_Blocked_List_Interval > 0
                        then 
                                set SLTBL_RTDB_Retrieve_Flag 
                                set SLTBL_RTDB_Retrieve.Key_Index = Request_Self_Learning_Healing.ID
                                next event SLTBL_RTDB_Retrieve
                                return
                        end if 	
                        set Req_SA_To_IQRY_Sending_Flag
			send(to = Glb_IDX_QRY_FSM_Customer_Index,
				event = Request_Self_Learning_Healing,
				ack = true)
			return
		end if
	case Index_Data_Query_Self_Healing_Return02_Read_ID2MDN
		if @.success
		then 
			if ID2MDN_RTDB_Record1.MDN != ""
			then
				set RTDB_Op_For = Index_Data_Query_Self_Healing_Return02_Del_GPRSSIM
				set GPRSSIM_Delete.Key_Index = ID2MDN_RTDB_Record1.MDN
			else
				reset RTDB_Op_For
			end if
			set ID2MDN_RTDB_Delete.Key_Index = ID2MDN_RTDB_Record1.I2M_Key
			next event ID2MDN_RTDB_Delete
			return
		elif @.tuple_not_found #ih_cr33608
		then
			set Retrieve_GPRSSIM_For = RGR_IDQ_Healing_Re02_Read_GPRSSIM
			set GPRSSIM_Retrieve.Key_Index = Request_Index_Service_Parameter_rec.ID
			next event GPRSSIM_Retrieve
			return
		end if
		next event Service_Terminate_Call
		return
	other
		next event Service_Terminate_Call
		return
	end test
end event ID2MDN_RTDB_Retrieve_Result

# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------ 
event ID2MDN_RTDB_Insert_Result
	test RTDB_Op_For
	case Sync_RTDB
		reset RTDB_Op_For
		next event Sync_Index_Data_With_OCS
		return
	other
		next event Service_Terminate_Call
		return
	end test
end event ID2MDN_RTDB_Insert_Result

# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------ 
event ID2MDN_RTDB_Replace_Result
	test RTDB_Op_For
	case Sync_RTDB
		reset RTDB_Op_For
		next event Sync_Index_Data_With_OCS
		return
	other
		next event Service_Terminate_Call
		return
	end test
end event ID2MDN_RTDB_Replace_Result

# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------ 
event ID2MDN_RTDB_Delete_Result
	test RTDB_Op_For
	case Sync_RTDB
		reset RTDB_Op_For
		next event Sync_Index_Data_With_OCS
		return
	case Index_Data_Query_Self_Healing_Return02_Del_GPRSSIM
		reset RTDB_Op_For
		next event GPRSSIM_Delete
		return
	other
		next event Service_Terminate_Call
		return
	end test
end event ID2MDN_RTDB_Delete_Result

# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------ 
# Event:       I_Sync_Index_Data_With_OCS
#
# Description:  the Interface for Sync GPRSSIM/ID2MDN rtdb according to the information in parameters.
#		
#------------------------------------------------------------------------------ 
event I_Sync_Index_Data_With_OCS
	reset Sync_Index_Data_Parameter_rec
	set Sync_Index_Data_Parameter_rec.MDN = @.MDN
	set Sync_Index_Data_Parameter_rec.SCP_Name = @.SCP_Name
	set Sync_Index_Data_Parameter_rec.IMSI_1 = @.IMSI_1
	if @.Extended_IMSI1 != "" && @.Extended_IMSI1 != @.UA #73254
	then
		set Sync_Index_Data_Parameter_rec.Extended_IMSI1 = @.Extended_IMSI1
	end if
	if @.Extended_IMSI2 != "" && @.Extended_IMSI2 != @.UA #73254
	then
		set Sync_Index_Data_Parameter_rec.Extended_IMSI2 = @.Extended_IMSI2
	end if
	set Sync_Index_Data_Parameter_rec.COSP_ID = @.COSP_ID
	set Sync_Index_Data_Parameter_rec.Provider_ID = @.Provider_ID
	set Sync_Index_Data_Parameter_rec.State = @.State
	set Sync_Index_Data_Parameter_rec.Old_IMSI_1 = @.Old_IMSI_1
	set Sync_Index_Data_Parameter_rec.Old_Extended_IMSI1 = @.Old_Extended_IMSI1
	set Sync_Index_Data_Parameter_rec.Old_Extended_IMSI2 = @.Old_Extended_IMSI2
	set Sync_Index_Data_Parameter_rec.OP = @.OP
	#72544 Service Sensitive Routing
	set Sync_Index_Data_Parameter_rec.Is_ASCP = @.Is_ASCP
	set Sync_Index_Data_Parameter_rec.Service_Type = @.Service_Type
	#SP28.7 VzW 73254
	set Sync_Index_Data_Parameter_rec.Subscriber_ID = @.Subscriber_ID
	set Sync_Index_Data_Parameter_rec.Old_Subscriber_ID = @.Old_Subscriber_ID
	set Sync_Index_Data_Parameter_rec.UA = @.UA

	#73178 when notification of RTDB change arrived , read the Common_Par_tbl for key mapping,	
	if @.OP == any("0", "1", "2", "3")
	then 
		if element_exists(Common_Par_tbl, Glb_GSL_SCP_Name)
		then
			set Common_Par_tbl.index = Glb_GSL_SCP_Name
			set Account_Id_Keymap_Plan = Common_Par_tbl.Account_ID_Keymap
		end if
		# set the flag to check if accound_id contains '-' later
		set Hierarchy_Keymap_flag
	end if 

	if @.MDN == any(@.Extended_IMSI1, @.Extended_IMSI2)
	then
		next event Sync_Index_Data_With_OCS_Result
		return
	end if
        #R28.10 73494
        if @.OP == any("","0","1","2")
        then
                set Index_Data_Sync_Flag  	
                if @.OP == any("", "0")
                then
                     set Index_Data_Sync_Insert_Flag
                end if 
        end if 
	
        test @.OP
	case any("", "0")
		if @.MDN != ""
		then
			#72544 Service Sensitive Routing
			if Number_Of_Collected_Index_Data > 1
			then
				set Glb_Temp_Flag_1 = Set_Info_Before_Read_GPRSSIM(Step_NULL, @.MDN)
				next event GPRSSIM_Retrieve
				return
			end if

			reset GPRSSIM_Record1
			set GPRSSIM_Record1.MSISDN = @.MDN
			set GPRSSIM_Record1.Host_SCP_Name = @.SCP_Name
			set GPRSSIM_Record1.Life_Cycle_State = @.State
			set GPRSSIM_Record1.Provider_ID = @.Provider_ID
			set GPRSSIM_Record1.COSP_ID = @.COSP_ID
			set Sync_RTDB_Step = Insert_Insert_in_GPRSSIM_Step1
			set RTDB_Op_For = Sync_RTDB
			next event GPRSSIM_Insert
			return
		end if
	case "1"
		if @.MDN != ""
		then
			#72544 Service Sensitive Routing
			if Number_Of_Collected_Index_Data > 1
			then
				set Glb_Temp_Flag_1 = Set_Info_Before_Read_GPRSSIM(Step_NULL, @.MDN)
				next event GPRSSIM_Retrieve
				return
			end if

			set GPRSSIM_Delete.Key_Index = @.MDN
			set Sync_RTDB_Step = Del_Delete_in_GPRSSIM_Step1
			set RTDB_Op_For = Sync_RTDB
			next event GPRSSIM_Delete
			return
		end if
	case "2"
		if @.MDN != ""
		then
			#72544 Service Sensitive Routing
			set Glb_Temp_Flag_1 = Set_Info_Before_Read_GPRSSIM(Step_NULL, @.MDN)
			next event GPRSSIM_Retrieve
			return
		end if

	case "3"
		if @.MDN != ""
		then
			if Request_Index_Service_Parameter_rec.ID_Type == "G"
			then
				set Sync_Index_Data_Parameter_rec.IMSI_1 = ""
			end if
			#72544 Service Sensitive Routing
			set Glb_Temp_Flag_1 = Set_Info_Before_Read_GPRSSIM(Step_NULL, @.MDN)
			#ih_cr31280
			if Number_Of_Collected_Index_Data > 1 && !Second_Sync_For_ASCP
			then
				next event Send_Check_GPRSSIM_Op_Lock
				return
			else
				next event GPRSSIM_Retrieve
				return
			end if
		end if
		#SP28.7 VzW 73254
	case "4"
		set ID2MDN_RTDB_Retrieve.Key_Index = @.MDN
		set Sync_RTDB_Step = UA_Del_ID2MDN_Retrieve_Step
		set RTDB_Op_For = Sync_RTDB
		next event ID2MDN_RTDB_Retrieve
		return
	case "5"
		set ID2MDN_RTDB_Retrieve.Key_Index = @.MDN
		set Sync_RTDB_Step = UA_Insert_ID2MDN_Retrieve_Step
		set RTDB_Op_For = Sync_RTDB
		next event ID2MDN_RTDB_Retrieve
		return
	other
		next event Sync_Index_Data_With_OCS_Result
		return
	end test

	next event Sync_Index_Data_With_OCS_Result
	return
end event I_Sync_Index_Data_With_OCS

#ih_cr31280
#----------------------------------------------------------------------------
# Event:	Send_Check_GPRSSIM_Op_Lock
#
# Description:	Send to server to check if the GPRSSIM is locked by other operation
#
#-----------------------------------------------------------------------------

event Send_Check_GPRSSIM_Op_Lock
dynamic
	Local_Server_XP_Dest			xp_dest
end dynamic
	set Local_Server_XP_Dest = routing_string!xp_server_lookup("Svr_Adm_Access_Key")
	if Local_Server_XP_Dest != xp_dest("")
	then
		reset Glb_Timer_Rec_Op
		set Glb_Timer_Rec_Op.t_type = tt_one_shot
		set Glb_Timer_Rec_Op.id = 1
		set Glb_Timer_Rec_Op.duration = 4
		timer!allocate(op = Glb_Timer_Rec_Op)
		set Clt_Svr!Lock_GPRSSIM_Op.Key = Sync_Index_Data_Parameter_rec.MDN
		xp_send(to = Local_Server_XP_Dest,
			event = Clt_Svr!Lock_GPRSSIM_Op,
			ack = true)
		return
	else
		next event GPRSSIM_Retrieve
		return
	end if
end event Send_Check_GPRSSIM_Op_Lock

#-----------------------------------------------------------------------------------
# Event: 	xp_send_completed
#
# Description:	
#
#-------------------------------------------------------------------------------------
event xp_send_completed
	return
end event xp_send_completed

#------------------------------------------------------------------------------------
# Event:	xp_send_failed
#
# Description:	
#
#-----------------------------------------------------------------------------------
event xp_send_failed
	set Glb_Timer_Return_Result = timer!cancel(1)
	next event GPRSSIM_Retrieve
	return
end event xp_send_failed

#------------------------------------------------------------------------------------
# Event:        Svr_Clt!Lock_GPRSSIM_Op_Result
#
# Description:  This event is used to handle the result from server for GPRSSIM lock check.
#
#-----------------------------------------------------------------------------------
event Svr_Clt!Lock_GPRSSIM_Op_Result

	if GPRSSIM_Lock_Error
	then
		#for timer allocate fail or timer expired scenario, logic has already
		#continued to do GPRSSIM Update. so just wait here.
		reset GPRSSIM_Lock_Error
		if !@.Success
		then
			set GPRSSIM_Locked_Flag
		end if
		return
	end if

	set Glb_Timer_Return_Result = timer!cancel(1)

	if @.Success #Success means GPRSSIM has been locked by other operation, it should wait.
	then
		reset Glb_Timer_Rec_Op
		set Glb_Timer_Rec_Op.t_type = tt_one_shot
		set Glb_Timer_Rec_Op.id = 2
		set Glb_Timer_Rec_Op.duration = Glb_Check_GPRSSIM_Lock_Timer
		timer!allocate(op = Glb_Timer_Rec_Op)
		return
	else
		set GPRSSIM_Locked_Flag
		next event GPRSSIM_Retrieve
		return
	end if
end event Svr_Clt!Lock_GPRSSIM_Op_Result

#------------------------------------------------------------------------------------
# Event:        timer!allocated
#
# Description:  timer allocated successfully.
#
#-----------------------------------------------------------------------------------
event timer!allocated
	return
end event timer!allocated

#------------------------------------------------------------------------------------
# Event:        timer!failed
#
# Description:  timer allocated failed, contine update the GPRSSIM.
#
#-----------------------------------------------------------------------------------
event timer!failed
	#both timer id =1 and id=2
	if @.id == 1
	then
		set GPRSSIM_Lock_Error
	end if

	next event GPRSSIM_Retrieve
	return
end event timer!failed

#-----------------------------------------------------------------------------------
# Event:	timer!expired
#
# Description:	handle timer time out.
#
#-----------------------------------------------------------------------------------
event timer!expired
	if @.id == 1
	then
		set GPRSSIM_Lock_Error
		next event GPRSSIM_Retrieve
		return
	end if

	if @.id == 2
	then
		if Retry_Check_Lock_Times < Glb_Retry_Check_Limit
		then 
			incr Retry_Check_Lock_Times #resolve previous operation unlock fail
			next event Send_Check_GPRSSIM_Op_Lock
			return
		end if

		next event GPRSSIM_Retrieve
		return
	end if
end event timer!expired

# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------ 
# Event:        Sync_Index_Data_With_OCS
#
# Description:  Sync GPRSSIM/ID2MDN rtdb according to the information in parameters.
#		
#------------------------------------------------------------------------------ 
event Sync_Index_Data_With_OCS
dynamic
	Local_Update_GPRSSIM_flag		flag
	Local_Upd_SCP_For_RTDB_OP		Upd_SCP_For_RTDB_OP_Enum	#72544
end dynamic
	test Sync_RTDB_Step
	case Insert_Insert_in_GPRSSIM_Step1
		reset IMSI_Changed_Flag 	#ih_cr35387
		if Sync_Index_Data_Parameter_rec.Extended_IMSI1 == ""
		then
			set Sync_RTDB_Step = Insert_Insert_in_GPRSSIM_Step2
			next event Sync_Index_Data_With_OCS
			return
		else
			#ih_cr35387
			set IMSI_Changed_Flag 	
			#SP28.7 VzW 73254
			set Glb_Temp_Flag_1 = Set_Info_Before_Read_ID2MDN(
				Insert_Insert_in_GPRSSIM_Step1,
				Sync_Index_Data_Parameter_rec.Extended_IMSI1)
			next event ID2MDN_RTDB_Retrieve
			return
		end if
		return
	case Insert_Insert_in_GPRSSIM_Step2
		reset IMSI_Changed_Flag		#ih_cr35387
		if Sync_Index_Data_Parameter_rec.Extended_IMSI2 == ""
		then
			set Sync_RTDB_Step = Insert_Insert_in_GPRSSIM_Step3
			next event Sync_Index_Data_With_OCS
		else
			set IMSI_Changed_Flag	#ih_cr35387
			#SP28.7 VzW 73254
			set Glb_Temp_Flag_1 = Set_Info_Before_Read_ID2MDN(
				Insert_Insert_in_GPRSSIM_Step2,
				Sync_Index_Data_Parameter_rec.Extended_IMSI2)
			next event ID2MDN_RTDB_Retrieve
			return

		end if
		return
	case Insert_Insert_in_GPRSSIM_Step3
		reset IMSI_Changed_Flag         #ih_cr35387
		if Sync_Index_Data_Parameter_rec.IMSI_1 == ""
		then

			next event Sync_Index_Data_With_OCS_Result
			return
		else
			set IMSI_Changed_Flag   #ih_cr35387
			set Glb_Temp_Flag_1 = Set_Info_Before_Read_ID2MDN(
				Insert_Insert_in_GPRSSIM_Step3,
				Sync_Index_Data_Parameter_rec.IMSI_1)

			next event ID2MDN_RTDB_Retrieve
			return
		end if
		return
	case Update_OP2or3_Step1
		#SP28.7 VzW 73254
		reset IMSI_Changed_Flag
		if Sync_Index_Data_Parameter_rec.Old_Extended_IMSI1 ==
			Sync_Index_Data_Parameter_rec.Extended_IMSI1
		then
			set Sync_Index_Data_Parameter_rec.Old_Extended_IMSI1 = ""
		else
			set IMSI_Changed_Flag
		end if

		if Sync_Index_Data_Parameter_rec.Extended_IMSI1 == ""
		then
			set Sync_RTDB_Step = Update_OP2or3_Step2
			next event Sync_Index_Data_With_OCS
			return
		else
			set Glb_Temp_Flag_1 = Set_Info_Before_Read_ID2MDN(
				Update_OP2or3_Step1,
				Sync_Index_Data_Parameter_rec.Extended_IMSI1)
			next event ID2MDN_RTDB_Retrieve
			return
		end if
	case Update_OP2or3_Step2
		##SP28.7 VzW 73254
		reset IMSI_Changed_Flag
		if Sync_Index_Data_Parameter_rec.Old_Extended_IMSI2 ==
			Sync_Index_Data_Parameter_rec.Extended_IMSI2
		then
			set Sync_Index_Data_Parameter_rec.Old_Extended_IMSI2 = ""
		else
			set IMSI_Changed_Flag
		end if

		if Sync_Index_Data_Parameter_rec.Extended_IMSI2 == ""
		then
			set Sync_RTDB_Step = Update_OP2or3_Step3
			next event Sync_Index_Data_With_OCS
			return
		else
			set Glb_Temp_Flag_1 = Set_Info_Before_Read_ID2MDN(
				Update_OP2or3_Step2,
				Sync_Index_Data_Parameter_rec.Extended_IMSI2)
			next event ID2MDN_RTDB_Retrieve
			return
		end if
	case Update_OP2or3_Step3
		if Sync_Index_Data_Parameter_rec.OP == "3"
		then
			if Sync_Index_Data_Parameter_rec.IMSI_1 == ""
			then
				if Request_Index_Service_Parameter_rec.ID_Type == "N"
				then
					set Sync_RTDB_Step = Del_ID2MDN_RTDB_Delete_Step
					set ID2MDN_RTDB_Delete.Key_Index = Request_Index_Service_Parameter_rec.ID
					set RTDB_Op_For = Sync_RTDB
					next event ID2MDN_RTDB_Delete
					return
					#73254
				else
					set Pre_Sync_RTDB_Step = Update_OP2or3_Step3
					set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
					if Sync_RTDB_Step == Step_NULL
					then
						set Sync_RTDB_Step = Insert_ID2MDN_RTDB_Insert_Step
					end if
					next event Sync_Index_Data_With_OCS
					return
				end if
			else
				#73254
				set Glb_Temp_Flag_1 = Set_Info_Before_Read_ID2MDN(
					Update_OP2or3_Step3,
					Sync_Index_Data_Parameter_rec.IMSI_1)
				next event ID2MDN_RTDB_Retrieve
				return
			end if 
		else 
			reset IMSI_Changed_Flag

			if Sync_Index_Data_Parameter_rec.Old_IMSI_1 == Sync_Index_Data_Parameter_rec.IMSI_1
			then
				set Sync_Index_Data_Parameter_rec.Old_IMSI_1 = ""
			else
				set IMSI_Changed_Flag
			end if 
			if Sync_Index_Data_Parameter_rec.IMSI_1 != ""
			then	
				#73254
				set Glb_Temp_Flag_1 = Set_Info_Before_Read_ID2MDN(
					Update_OP2or3_Step3,
					Sync_Index_Data_Parameter_rec.IMSI_1)
				next event ID2MDN_RTDB_Retrieve
				return
			else
				set Sync_Index_Data_Parameter_rec.IMSI_1 = Sync_Index_Data_Parameter_rec.Old_IMSI_1
				set Sync_Index_Data_Parameter_rec.Extended_IMSI1 = Sync_Index_Data_Parameter_rec.Old_Extended_IMSI1
				set Sync_Index_Data_Parameter_rec.Extended_IMSI2 = Sync_Index_Data_Parameter_rec.Old_Extended_IMSI2
				set Sync_RTDB_Step = Del_Delete_in_GPRSSIM_Step1
				set RTDB_Op_For = Sync_RTDB
				next event Sync_Index_Data_With_OCS
				return
			end if
		end if

	case Del_Delete_in_GPRSSIM_Step1
		if Sync_Index_Data_Parameter_rec.Extended_IMSI1 == ""
		then
			set Sync_RTDB_Step = Del_Delete_in_GPRSSIM_Step2
			next event Sync_Index_Data_With_OCS
			return
		else
			#SP28.7 VzW 73254
			set Glb_Temp_Flag_1 = Set_Info_Before_Read_ID2MDN(
				Del_Delete_in_GPRSSIM_Step1,
				Sync_Index_Data_Parameter_rec.Extended_IMSI1)
			next event ID2MDN_RTDB_Retrieve
			return
		end if
		return
	case Del_Delete_in_GPRSSIM_Step2
		if Sync_Index_Data_Parameter_rec.Extended_IMSI2 == ""
		then
			set Sync_RTDB_Step = Del_Delete_in_GPRSSIM_Step3
			next event Sync_Index_Data_With_OCS
			return
		else
			#SP28.7 VzW 73254
			set Glb_Temp_Flag_1 = Set_Info_Before_Read_ID2MDN(
				Del_Delete_in_GPRSSIM_Step2,
				Sync_Index_Data_Parameter_rec.Extended_IMSI2)
			next event ID2MDN_RTDB_Retrieve
			return
		end if
		return
	case Del_Delete_in_GPRSSIM_Step3
		if Sync_Index_Data_Parameter_rec.IMSI_1 == ""
		then
			# set  Sync_Index_Data_With_OCS_Result.success
			next event Sync_Index_Data_With_OCS_Result
			return
		else
			set Glb_Temp_Flag_1 = Set_Info_Before_Read_ID2MDN(
				Del_Delete_in_GPRSSIM_Step3,
				Sync_Index_Data_Parameter_rec.IMSI_1)
			next event ID2MDN_RTDB_Retrieve
			return
		end if
	case Insert_ID2MDN_RTDB_Retrieve_Step
		#SP28.7 VzW 73254
		set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
		if Sync_RTDB_Step == Step_NULL
		then
			set Sync_RTDB_Step = Insert_ID2MDN_RTDB_Insert_Step
		end if

		if Sync_Index_Data_Parameter_rec.success
		then
			if ID2MDN_RTDB_Record1.MDN == ""
			then
				set ID2MDN_RTDB_Record1.MDN = Sync_Index_Data_Parameter_rec.MDN
				set ID2MDN_RTDB_Flag.MDN
				set RTDB_Op_For = Sync_RTDB
				next event ID2MDN_RTDB_Replace
				return
			else
				if ID2MDN_RTDB_Record1.MDN != Sync_Index_Data_Parameter_rec.MDN
				then
					#73254
					if Sync_Index_Data_Parameter_rec.OP == any("0", "2") &&
						IMSI_Changed_Flag &&
						Not_Keep_Old_ID2MDN_Info(Sync_Index_Data_Parameter_rec.OP)
					then
						set ID2MDN_RTDB_Record1.MDN = Sync_Index_Data_Parameter_rec.MDN
						set ID2MDN_RTDB_Flag.MDN
						set RTDB_Op_For = Sync_RTDB
						next event ID2MDN_RTDB_Replace
						return
					end if

					set Old_Pre_Sync_RTDB_Step = Pre_Sync_RTDB_Step #73254
					set Pre_Sync_RTDB_Step = Insert_ID2MDN_RTDB_Retrieve_Step #72544
					set Sync_RTDB_Step = Insert_GPRSSIM_Retrieve_Step
					set GPRSSIM_Retrieve.Key_Index = ID2MDN_RTDB_Record1.MDN
					set Retrieve_GPRSSIM_For = RGR_Index_Data_Sync_Update
					#set RTDB_Op_For = Sync_RTDB
					next event GPRSSIM_Retrieve
					return
				end if 
				if Sync_Index_Data_Parameter_rec.OP == "2"
					&& Pre_Sync_RTDB_Step == Update_OP2or3_Step3 #73254
				then
					set Sync_Index_Data_Parameter_rec.IMSI_1 = Sync_Index_Data_Parameter_rec.Old_IMSI_1
					set Sync_Index_Data_Parameter_rec.Extended_IMSI1 = Sync_Index_Data_Parameter_rec.Old_Extended_IMSI1
					set Sync_Index_Data_Parameter_rec.Extended_IMSI2 = Sync_Index_Data_Parameter_rec.Old_Extended_IMSI2
					set Sync_RTDB_Step = Del_Delete_in_GPRSSIM_Step1
					next event Sync_Index_Data_With_OCS
					return
				end if
				next event Sync_Index_Data_With_OCS
				return
			end if
		elif Sync_Index_Data_Parameter_rec.tuple_not_found
		then
			set ID2MDN_RTDB_Record1.I2M_Key = ID2MDN_RTDB_Retrieve.Key_Index
			set ID2MDN_RTDB_Record1.MDN = Sync_Index_Data_Parameter_rec.MDN
			set RTDB_Op_For = Sync_RTDB
			next event ID2MDN_RTDB_Insert
			return
		else
			next event Sync_Index_Data_With_OCS_Result
			return
		end if 
	case Insert_GPRSSIM_Retrieve_Step
		if Sync_Index_Data_Parameter_rec.success
		then
			#SP28.7 VzW 73254
			if Pre_Sync_RTDB_Step == UA_Insert_ID2MDN_Retrieve_Step
			then
				if Not_Keep_Old_ID2MDN_Info(Sync_Index_Data_Parameter_rec.OP)
				then
					set Sync_RTDB_Step = Insert_ID2MDN_RTDB_Insert_Step
					set ID2MDN_RTDB_Record1.MDN
						= Sync_Index_Data_Parameter_rec.Subscriber_ID
					set ID2MDN_RTDB_Flag.MDN
					set RTDB_Op_For = Sync_RTDB
					next event ID2MDN_RTDB_Replace
					return
				else
					#keep old ID2MDN record
					send_om(
	                                        msg_id = counter("30" : "103"),  #SP28.16 RDAF729606
						msg_class = GSL_Internal_Assert_Message_Class,
						poa = GSL_Internal_Assert_Priority,
						title = "ASSERT=103, SPA=EPPSM",
						message = " MDN is not null and different but keep old ID2MDN! " :
						"ID2MDN.MDN = " : ID2MDN_RTDB_Record1.MDN :
						"\n Current MDN = " : Sync_Index_Data_Parameter_rec.Subscriber_ID,
						message2 = "\nCall Instance ID = " : string(call_index()) :
						"\nScenario Location = ID2MDN_RTDB_Retrieve_Result "
						)
					next event Sync_Index_Data_With_OCS_Result
					return
				end if
			end if

			#72544 Service Sensitive Routing
			if Pre_Sync_RTDB_Step != Insert_ID2MDN_RTDB_Retrieve_Step
			then
				set Local_Update_GPRSSIM_flag = Upd_SCP_For_Insert_Sync_Data()
				set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
				if Sync_RTDB_Step == Step_NULL
				then
					next event Sync_Index_Data_With_OCS_Result
					return
				end if

				if Local_Update_GPRSSIM_flag
				then
					set RTDB_Op_For = Sync_RTDB
					next event GPRSSIM_Replace
					return
			        elif Index_Data_Sync_Insert_Flag
                                then
                                        incr Glb_Service_Measurement_Rec.Failed_Insert_Due_Sub_Exist	
                                end if

				next event Sync_Index_Data_With_OCS
				return
			end if
			#end 72544

			#73254
			set Pre_Sync_RTDB_Step = Old_Pre_Sync_RTDB_Step
			set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
			if Sync_RTDB_Step == Step_NULL
			then
				set Sync_RTDB_Step = Insert_ID2MDN_RTDB_Insert_Step
			end if

			next event Sync_Index_Data_With_OCS
			return
		elif Sync_Index_Data_Parameter_rec.tuple_not_found
		then  
			#72544 Service Sensitive Routing
			if Pre_Sync_RTDB_Step != Insert_ID2MDN_RTDB_Retrieve_Step
				&& Pre_Sync_RTDB_Step != UA_Insert_ID2MDN_Retrieve_Step #73254
			then
				set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
				if Sync_RTDB_Step == Step_NULL
				then
					next event Sync_Index_Data_With_OCS_Result
					return
				end if

				set Glb_Temp_Flag_1 = Set_GPRSSIM_Info_For_Insert()
				set RTDB_Op_For = Sync_RTDB
				next event GPRSSIM_Insert
				return
			end if
			#end 72544 

			# generate alarm message with assert code 103
			send_om(
	                        msg_id = counter("30" : "103"),  #SP28.16 RDAF729606
				msg_class = GSL_Internal_Assert_Message_Class,
				poa = GSL_Internal_Assert_Priority,
				title = "ASSERT=103, SPA=EPPSM",
				message = " MDN is not null and different ! " :
				"ID2MDN.MDN = " : ID2MDN_RTDB_Record1.MDN :
				"\n Current MDN = " : Sync_Index_Data_Parameter_rec.MDN,
				message2 = "\nCall Instance ID = " : string(call_index()) :
				"\nScenario Location = ID2MDN_RTDB_Retrieve_Result "
				)

			#update ID2MDN.MDN
			#SP28.7 VzW 73254
			set Pre_Sync_RTDB_Step = Old_Pre_Sync_RTDB_Step
			set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
			if Sync_RTDB_Step == Step_NULL
			then
				set Sync_RTDB_Step = Insert_ID2MDN_RTDB_Insert_Step
			end if
			if Pre_Sync_RTDB_Step == UA_Insert_ID2MDN_Retrieve_Step
			then
				set ID2MDN_RTDB_Record1.MDN
					= Sync_Index_Data_Parameter_rec.Subscriber_ID
			else
				set ID2MDN_RTDB_Record1.MDN = Sync_Index_Data_Parameter_rec.MDN
			end if
			set ID2MDN_RTDB_Flag.MDN
			set RTDB_Op_For = Sync_RTDB
			next event ID2MDN_RTDB_Replace
			return
		else
			next event Sync_Index_Data_With_OCS_Result
			return
		end if

	case Del_ID2MDN_RTDB_Retrieve_Step
		#SP28.7 VzW 73254
		set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
		if Sync_RTDB_Step == Step_NULL
		then
			set Sync_RTDB_Step = Del_ID2MDN_RTDB_Delete_Step
		end if

		if Sync_Index_Data_Parameter_rec.success
		then
			#ih_cr33608
			if Pre_Sync_RTDB_Step == Update_OP2or3_Step4
			then
				set ID2MDN_RTDB_Delete.Key_Index = Request_Index_Service_Parameter_rec.ID
				set RTDB_Op_For = Sync_RTDB
				next event ID2MDN_RTDB_Delete
				return
			end if

			if ID2MDN_RTDB_Record1.MDN != "" && ID2MDN_RTDB_Record1.MDN != Sync_Index_Data_Parameter_rec.MDN
			then
				set Old_Pre_Sync_RTDB_Step = Pre_Sync_RTDB_Step #73254
				set Pre_Sync_RTDB_Step = Del_ID2MDN_RTDB_Retrieve_Step #72544
				set Sync_RTDB_Step = Del_GPRSSIM_Retrieve_Step
				set GPRSSIM_Retrieve.Key_Index = ID2MDN_RTDB_Record1.MDN
				set Retrieve_GPRSSIM_For = RGR_Index_Data_Sync_Update
				#set RTDB_Op_For = Sync_RTDB
				next event GPRSSIM_Retrieve
				return
			elif Number_Of_Collected_Index_Data == 1 || ID2MDN_RTDB_Record1.MDN == "" || GPRSSIM_Del_Flag || Sync_Index_Data_Parameter_rec.OP == "2"
			then
				set ID2MDN_RTDB_Delete.Key_Index = ID2MDN_RTDB_Retrieve.Key_Index
				set RTDB_Op_For = Sync_RTDB
				next event ID2MDN_RTDB_Delete
				return
			end if
		end if	

		next event Sync_Index_Data_With_OCS
		return

	case Del_GPRSSIM_Retrieve_Step
		if Sync_Index_Data_Parameter_rec.success
		then
			#SP28.7 VzW 73254
			if Pre_Sync_RTDB_Step == UA_Del_ID2MDN_Retrieve_Step
			then
				next event Sync_Index_Data_With_OCS_Result
				return
			end if

			#72544 Service Sensitive Routing
			if Pre_Sync_RTDB_Step != Del_ID2MDN_RTDB_Retrieve_Step
			then
				set Local_Upd_SCP_For_RTDB_OP = Upd_SCP_For_Del_Sync_Data()
				set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
				if Sync_RTDB_Step == Step_NULL
				then
					next event Sync_Index_Data_With_OCS_Result
					return
				end if

				test Local_Upd_SCP_For_RTDB_OP
				case RTDB_No_Change
					next event Sync_Index_Data_With_OCS
					return
				case RTDB_Update
					set RTDB_Op_For = Sync_RTDB
					next event GPRSSIM_Replace
					return
				case RTDB_Delete
					set GPRSSIM_Del_Flag
					set RTDB_Op_For = Sync_RTDB
					next event GPRSSIM_Delete
					return
				end test
			end if
			#end 72544
			#SP28.7 VzW 73254
			set Pre_Sync_RTDB_Step = Old_Pre_Sync_RTDB_Step
			set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
			if Sync_RTDB_Step == Step_NULL
			then
				set Sync_RTDB_Step = Del_ID2MDN_RTDB_Delete_Step
			end if

			next event Sync_Index_Data_With_OCS
			return
		elif Sync_Index_Data_Parameter_rec.tuple_not_found
		then  
			#72544 Service Sensitive Routing
			if Pre_Sync_RTDB_Step != Del_ID2MDN_RTDB_Retrieve_Step
				&& Pre_Sync_RTDB_Step != UA_Del_ID2MDN_Retrieve_Step #73254
			then
				set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
				if Sync_RTDB_Step == Step_NULL
				then
					next event Sync_Index_Data_With_OCS_Result
					return
				end if
				next event Sync_Index_Data_With_OCS
				return
			end if
			#end 72544

			send_om(
	                        msg_id = counter("30" : "103"),  #SP28.16 RDAF729606
				msg_class = GSL_Internal_Assert_Message_Class,
				poa = GSL_Internal_Assert_Priority,
				title = "ASSERT=103, SPA=EPPSM",
				message = " MDN is not null and different !" :
				"ID2MDN.MDN = " : ID2MDN_RTDB_Record1.MDN :
				"\n Current MDN = " : Sync_Index_Data_Parameter_rec.MDN,
				message2 = "\nCall Instance ID = " : string(call_index()) :
				"\nScenario Location = ID2MDN_RTDB_Retrieve_Result "
				)

			#delete ID2MDN record
			#SP28.7 VzW 73254
			set Pre_Sync_RTDB_Step = Old_Pre_Sync_RTDB_Step
			set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
			if Sync_RTDB_Step == Step_NULL
			then
				set Sync_RTDB_Step = Del_ID2MDN_RTDB_Delete_Step
			end if
			if Pre_Sync_RTDB_Step == UA_Del_ID2MDN_Retrieve_Step
			then
				set ID2MDN_RTDB_Delete.Key_Index = Sync_Index_Data_Parameter_rec.MDN
			else
				set ID2MDN_RTDB_Delete.Key_Index = ID2MDN_RTDB_Retrieve.Key_Index
			end if

			set RTDB_Op_For = Sync_RTDB
			next event ID2MDN_RTDB_Delete
			return
		else
			next event Sync_Index_Data_With_OCS_Result
			return
		end if

	case Update_GPRSSIM_Retrieve_Step
		if Sync_Index_Data_Parameter_rec.success
		then
			reset Local_Update_GPRSSIM_flag
			#72544 Service Sensitive Routing
			if Number_Of_Collected_Index_Data > 1
			then
				set Local_Update_GPRSSIM_flag = Upd_SCP_For_Insert_Sync_Data()
			else
				if GPRSSIM_Record1.Host_SCP_Name != Sync_Index_Data_Parameter_rec.SCP_Name
				then
					set Local_Update_GPRSSIM_flag
					set GPRSSIM_Record1.Host_SCP_Name = Sync_Index_Data_Parameter_rec.SCP_Name
					set GPRSSIM_Flag.Host_SCP_Name
				end if 
				if GPRSSIM_Record1.Life_Cycle_State != Sync_Index_Data_Parameter_rec.State && Sync_Index_Data_Parameter_rec.State != ""
				then
					set Local_Update_GPRSSIM_flag
					set GPRSSIM_Record1.Life_Cycle_State = Sync_Index_Data_Parameter_rec.State
					set GPRSSIM_Flag.Life_Cycle_State
				end if
				if GPRSSIM_Record1.Provider_ID != Sync_Index_Data_Parameter_rec.Provider_ID && Sync_Index_Data_Parameter_rec.Provider_ID != ""
				then    
					set Local_Update_GPRSSIM_flag
					set GPRSSIM_Record1.Provider_ID = Sync_Index_Data_Parameter_rec.Provider_ID
					set GPRSSIM_Flag.Provider_ID
				end if
				if GPRSSIM_Record1.COSP_ID != Sync_Index_Data_Parameter_rec.COSP_ID && Sync_Index_Data_Parameter_rec.COSP_ID != ""
				then
					set Local_Update_GPRSSIM_flag
					set GPRSSIM_Record1.COSP_ID = Sync_Index_Data_Parameter_rec.COSP_ID
					set GPRSSIM_Flag.COSP_ID
				end if
			end if

			#72544
			set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
			if Sync_RTDB_Step == Step_NULL
			then
				next event Sync_Index_Data_With_OCS_Result
				return
			end if

			if Local_Update_GPRSSIM_flag
			then
				set RTDB_Op_For = Sync_RTDB
				next event GPRSSIM_Replace
				return
			end if
			next event Sync_Index_Data_With_OCS
			return
		elif Sync_Index_Data_Parameter_rec.tuple_not_found
		then
			#72544 Service Sensitive Routing
			set Glb_Temp_Flag_1 = Set_GPRSSIM_Info_For_Insert()
			set Sync_RTDB_Step = Get_Next_State_For_Sync_Data()
			if Sync_RTDB_Step == Step_NULL
			then
				next event Sync_Index_Data_With_OCS_Result
				return
			end if
			set Dup_Insert_Still_Update
			set RTDB_Op_For = Sync_RTDB
			next event GPRSSIM_Insert
			return
		else
			next event Sync_Index_Data_With_OCS_Result
			return
		end if 
	case Insert_ID2MDN_RTDB_Insert_Step
		if Sync_Index_Data_Parameter_rec.OP == "2"
			&& Pre_Sync_RTDB_Step == Update_OP2or3_Step3 #73254
		then
			set Sync_Index_Data_Parameter_rec.IMSI_1 = Sync_Index_Data_Parameter_rec.Old_IMSI_1
			set Sync_Index_Data_Parameter_rec.Extended_IMSI1 = Sync_Index_Data_Parameter_rec.Old_Extended_IMSI1
			set Sync_Index_Data_Parameter_rec.Extended_IMSI2 = Sync_Index_Data_Parameter_rec.Old_Extended_IMSI2
			set Sync_RTDB_Step = Del_Delete_in_GPRSSIM_Step1
			next event Sync_Index_Data_With_OCS
			return
		end if
		next event Sync_Index_Data_With_OCS_Result
		return
	case Del_ID2MDN_RTDB_Delete_Step
		next event Sync_Index_Data_With_OCS_Result
		return
		#SP28.7 Vzw 73254 new added for UA
	case Update_OP2or3_Step4
		if Sync_Index_Data_Parameter_rec.UA != ""
		then
			set Glb_Temp_Flag_1 = Set_Info_Before_Read_ID2MDN(
				Update_OP2or3_Step4,
				Sync_Index_Data_Parameter_rec.UA)
			next event ID2MDN_RTDB_Retrieve
			return
		else
			if Request_Index_Service_Parameter_rec.ID == Sync_Index_Data_Parameter_rec.MDN
			then
				#ih_cr33608
				set Pre_Sync_RTDB_Step = Update_OP2or3_Step4
				set ID2MDN_RTDB_Retrieve.Key_Index = Request_Index_Service_Parameter_rec.ID
				set RTDB_Op_For = Sync_RTDB
				set Sync_RTDB_Step = Del_ID2MDN_RTDB_Retrieve_Step
				next event ID2MDN_RTDB_Retrieve
				return
			end if
		end if
		next event Sync_Index_Data_With_OCS_Result
		return
	case UA_Del_ID2MDN_Retrieve_Step
		if Sync_Index_Data_Parameter_rec.success
		then
			if ID2MDN_RTDB_Record1.MDN != "" && ID2MDN_RTDB_Record1.MDN != Sync_Index_Data_Parameter_rec.Subscriber_ID
			then
				set Old_Pre_Sync_RTDB_Step = UA_Del_ID2MDN_Retrieve_Step
				set Pre_Sync_RTDB_Step = UA_Del_ID2MDN_Retrieve_Step
				set Sync_RTDB_Step = Del_GPRSSIM_Retrieve_Step
				set GPRSSIM_Retrieve.Key_Index = ID2MDN_RTDB_Record1.MDN
				set Retrieve_GPRSSIM_For = RGR_Index_Data_Sync_Update
				next event GPRSSIM_Retrieve
				return
			else
				set Sync_RTDB_Step = Del_ID2MDN_RTDB_Delete_Step
				set ID2MDN_RTDB_Delete.Key_Index = Sync_Index_Data_Parameter_rec.MDN
				set RTDB_Op_For = Sync_RTDB
				next event ID2MDN_RTDB_Delete
				return
			end if
		end if
		next event Sync_Index_Data_With_OCS_Result
		return
	case UA_Insert_ID2MDN_Retrieve_Step
		if Sync_Index_Data_Parameter_rec.success
		then
			if ID2MDN_RTDB_Record1.MDN == "" ||
				Sync_Index_Data_Parameter_rec.Old_Subscriber_ID == ID2MDN_RTDB_Record1.MDN
			then
				set Sync_RTDB_Step = Insert_ID2MDN_RTDB_Insert_Step
				set ID2MDN_RTDB_Record1.MDN
					= Sync_Index_Data_Parameter_rec.Subscriber_ID
				set ID2MDN_RTDB_Flag.MDN
				set RTDB_Op_For = Sync_RTDB
				next event ID2MDN_RTDB_Replace
				return
			elif ID2MDN_RTDB_Record1.MDN != Sync_Index_Data_Parameter_rec.Subscriber_ID
			then
				set Old_Pre_Sync_RTDB_Step = UA_Insert_ID2MDN_Retrieve_Step
				set Pre_Sync_RTDB_Step = UA_Insert_ID2MDN_Retrieve_Step
				set Sync_RTDB_Step = Insert_GPRSSIM_Retrieve_Step
				set GPRSSIM_Retrieve.Key_Index = ID2MDN_RTDB_Record1.MDN
				set Retrieve_GPRSSIM_For = RGR_Index_Data_Sync_Update
				next event GPRSSIM_Retrieve
				return
			else   
				next event Sync_Index_Data_With_OCS_Result
				return
			end if
		elif Sync_Index_Data_Parameter_rec.tuple_not_found
		then
			set Sync_RTDB_Step = Insert_ID2MDN_RTDB_Insert_Step
			set ID2MDN_RTDB_Record1.I2M_Key = Sync_Index_Data_Parameter_rec.MDN
			set ID2MDN_RTDB_Record1.MDN = Sync_Index_Data_Parameter_rec.Subscriber_ID
			set RTDB_Op_For = Sync_RTDB
			next event ID2MDN_RTDB_Insert
			return
		else
			next event Sync_Index_Data_With_OCS_Result
			return
		end if
	case Upd_For_Online_Hier_Step			#76541
		next event Check_Online_Hier_Group
		return
	end test
	next event Sync_Index_Data_With_OCS_Result
	return
end event Sync_Index_Data_With_OCS

# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------ 
event Sync_Index_Data_With_OCS_Result
dynamic
	Local_Server_XP_Dest			xp_dest	#ih_cr31280
end dynamic
	# SP28.5 Vzw 72544
	if Need_Sync_ASCP_Flag && Alternative_SCP_Info.SCP_Name != ""
	then
		set Second_Sync_For_ASCP #ih_cr31280
		reset Need_Sync_ASCP_Flag
		reset I_Sync_Index_Data_With_OCS
		set I_Sync_Index_Data_With_OCS.OP = "3"
		set I_Sync_Index_Data_With_OCS.MDN = Sync_Index_Data_Parameter_rec.MDN
		set I_Sync_Index_Data_With_OCS.IMSI_1 = Alternative_SCP_Info.IMSI1
		set I_Sync_Index_Data_With_OCS.SCP_Name = Alternative_SCP_Info.SCP_Name
		set I_Sync_Index_Data_With_OCS.Service_Type = Alternative_SCP_Info.Service_Type
		#SP28.7 VzW 73254
		set I_Sync_Index_Data_With_OCS.Extended_IMSI1 = Alternative_SCP_Info.E_IMSI1
		set I_Sync_Index_Data_With_OCS.Extended_IMSI2 = Alternative_SCP_Info.E_IMSI2
		set I_Sync_Index_Data_With_OCS.UA = Alternative_SCP_Info.UA

		set I_Sync_Index_Data_With_OCS.Is_ASCP
		next event I_Sync_Index_Data_With_OCS
		return
	end if

	#ih_cr31280
	if GPRSSIM_Locked_Flag
	then
		reset Second_Sync_For_ASCP
		reset GPRSSIM_Locked_Flag
		set Clt_Svr!Unlock_GPRSSIM_Op.Key = Sync_Index_Data_Parameter_rec.MDN
		set Local_Server_XP_Dest = routing_string!xp_server_lookup("Svr_Adm_Access_Key")
		if Local_Server_XP_Dest != xp_dest("")
		then
			xp_send(to = Local_Server_XP_Dest,
				event = Clt_Svr!Unlock_GPRSSIM_Op,
				ack = false)
		end if
	end if

	next event Service_Terminate_Call
end event  Sync_Index_Data_With_OCS_Result

#------------------------------------------------------------------------------	
# Event:	Check_Online_Hier_Group
#
#		F76541
# Description:	get all the hierarchy in the branch of healing group 
#		
#------------------------------------------------------------------------------	
event Check_Online_Hier_Group
dynamic
	Local_Account_Number		counter
	Local_Group_ID			string
end dynamic
	if cDB_RTDB_Enabled
	then
		set Retrieve_CD_RTDB_Step = Upd_GPRSSIM_For_Online
		set Group_ID = Sync_Index_Data_Parameter_rec.MDN
		set Request_CDB_RTDB_Retrieve.key_index = Sync_Index_Data_Parameter_rec.MDN : ":"
		set CDB_RTDB_Max_Records = 1
		reset RTDB_Exact_Match
		next event Request_CDB_RTDB_Retrieve
		return
	else
		set Local_Group_ID = Sync_Index_Data_Parameter_rec.MDN

		while (true)
		do
			set Glb_Temp_String2 = Local_Group_ID: ":"
			set Glb_Temp_String2 = index_next(Centralized_Group_tbl, Glb_Temp_String2)
			Parse_Object(":", Glb_Temp_String2)

			if Local_Group_ID == Glb_Parsed && Glb_Remainder != "" 
			then
				set Local_Group_ID = Glb_Remainder
				incr Local_Account_Number
				insert into Account_ID_List_tbl at Local_Account_Number
				set Account_ID_List_tbl.Account_ID = Glb_Remainder
				set Total_Account_Number = Local_Account_Number

				if Centralized_Group_tbl[Glb_Temp_String2].Top_Account_Indicator
				then
					exit while
				end if
			else
				exit while
			end if
		end while
				
		set Account_ID_Pos = 1
		next event Upd_GPRSSIM_For_Online_Hier
		return
	end if
end event Check_Online_Hier_Group

#------------------------------------------------------------------------------	
# Event:	Upd_GPRSSIM_For_Online_Hier
#
# Description:	update GPRSSIM for all the group for the branch of healing group.
#
#------------------------------------------------------------------------------	
event Upd_GPRSSIM_For_Online_Hier
	while Account_ID_Pos <= Total_Account_Number
	do
		if element_exists(Account_ID_List_tbl, Account_ID_Pos)
		then
			set Account_ID_List_tbl.index = Account_ID_Pos
			set Retrieve_GPRSSIM_For = RGR_Sync_Group_Host
			set GPRSSIM_Retrieve.Key_Index = Account_ID_List_tbl.Account_ID
			next event GPRSSIM_Retrieve
			return
		end if
		incr Account_ID_Pos
	end while
	next event Sync_Index_Data_With_OCS_Result
	return
end event Upd_GPRSSIM_For_Online_Hier

#------------------------------------------------------------------------------	
# Event:	P_S!Request_Hierarchy_Information
#
# Description:	Obtain the information from the	LDAP, and begain the logic to 
#		get the	primary	account	information.
#
#------------------------------------------------------------------------------	
event P_S!Request_Hierarchy_Information
	set Primary_Account_ID = @.Primary_Account_ID
	set Secondary_Account_ID = @.Secondary_Account_ID
	# V10.5 62977 spa678628dA
	set Sponsoring_Account_ID = @.Sponsoring_Account_ID
	# SP27.9 VFCZ 70577
	set Query_Group_Operation = @.Operation
	# V10.13 66403
	set Account_ID_List_tbl[] = @.Account_ID_List_tbl[]
	set Total_Account_Number = @.Total_Account_Number

	set Inter_eCS_COMM_FSM_Call_Index = @.Call_Index
	set Retrieve_HM_RTDB_Step = DH_Step_Get_Primary_Account_Inf
	set HM_RTDB_Key = Primary_Account_ID
	
	# SP28.14 75195
	if cDB_RTDB_Enabled
	then
		if GLB_CDB_RTDB_Not_Used
		then
                        #SP28.16 RDAF729606
                        Parse_Object(",", string(Glb_RTDB_Data_Assert_Title))
                        if Glb_Parse_Temp_Count > 0
                        then
                        	set Glb_Temp_String_Parsed = map(Glb_Parsed,
                        		"abcdefghijklmnopqrstuvwxzyABCDEFGHIJKLMNOPQRSTUVWXYZ= ", "")
                        else
                        	set Glb_Temp_String_Parsed = "000"
                        end if
			
			send_om(
	                        msg_id = counter("30" : Glb_Temp_String_Parsed),
				msg_class = GSL_Assert_Message_Class,
				poa = GSL_Assert_Priority,
				title = Glb_RTDB_Data_Assert_Title,
				message = "Data Provisioning Error - Invalid cDB RTDB Mode",
				message2 =
				"\nCall Instance ID = " : string(call_index()) :
				"\nScenario Location = P_S!Request_Hierarchy_Information" 
				)
			next event Service_Terminate_Call
			return
		end if
	end if
	
	#SP28.11 VFQ feature F74754
	set Online_Hierarchy_Flag = @.Online_Hierarchy
	# V10.13 66403
	if Secondary_Account_ID == "QUYINDEXDB"
	then
		set Account_ID_Pos = 1
		next event Request_Query_Index_DB
		return
	end if

	# VFGH Feature 69452
	if Secondary_Account_ID == "QUYCOSP"
	then
		set Retrieve_GPRSSIM_For = RGR_IntraCOS_Account
		set GPRSSIM_Retrieve.Key_Index = Primary_Account_ID
		next event GPRSSIM_Retrieve
		return
	end if

	# SP27.9 VFCZ 70577
	if Query_Group_Operation == any("0", "1", "2")
	then
		limit(next_events = 1000)
		#SP28.6 72000
		if Online_Hierarchy_Flag
		then 
			next event Request_Query_Hier_Info
			return
		else
			set Account_ID_Pos = 1
			next event Request_Query_Group_Info
			return
		end if
	end if
	# SP28.7, Feature 72483
	if Query_Group_Operation == "3"
	then
		next event Req_Qry_Hier_Info_For_Top_Acct
		return
	end if
	# SP28.7, Feature 72483 end
	
	#72817
	if Query_Group_Operation == "4"&& Sponsoring_Account_ID != ""
	then
		set Retrieve_GPRSSIM_For = RGR_Sponsoring_Account
		set GPRSSIM_Retrieve.Key_Index = Sponsoring_Account_ID
		next event GPRSSIM_Retrieve
		return
	end if

	# V10.5 62977 spa678628dA, Get information for Sponsoring Account
	if Sponsoring_Account_ID != ""
	then	
		reset Sponsoring_Hierarchy_Account_Indicator
		if(element_exists(Hierarchy_Definition_tbl, Sponsoring_Account_ID))
		then		
			set Hierarchy_Definition_tbl.index = Sponsoring_Account_ID
			set Sponsoring_Top_Level_Account_ID
				= Hierarchy_Definition_tbl.Next_Level_Account_ID

			#check its legitimacy, if the Sponsoring_Top_Level_Account_ID is 
			# not exist in the HD table, then it will be think as
			# Insufficient levels, so we think it's the top level.		
			if(Sponsoring_Top_Level_Account_ID == "")
			then			
				#For the Sponsoring_Top_Level_Account_ID is "",			
				#Check if Sponsoring Account is Simple Account or is
				#BR Account (BR1 Level)			
				test Hierarchy_Definition_tbl.Billing_Responsibility_Level
				case 0
					# Sponsor is Simple Account
					set Sponsoring_Hierarchy_Account_Indicator = "0"
					set Sponsoring_MSISDN = Hierarchy_Definition_tbl.Account_MSISDN
				case 1
					set Sponsoring_Hierarchy_Account_Indicator = "1"
					set Sponsoring_Top_Level_Account_ID = Sponsoring_Account_ID
				other			
				end test		
			else		       
				if(element_exists(Hierarchy_Definition_tbl, Sponsoring_Top_Level_Account_ID))
				then			
					set Hierarchy_Definition_tbl.index = Sponsoring_Top_Level_Account_ID
					#only support 2 level
					if(Hierarchy_Definition_tbl.Next_Level_Account_ID == "")
					then			
						#check if Sponsoring Account is BR Account (BR2 Level)
						test Hierarchy_Definition_tbl.Billing_Responsibility_Level
						case 2
							set Sponsoring_Hierarchy_Account_Indicator = "1"
						other			
						end test
					end if		       
				end if #if (element_exists(Hierarchy_Definition_tbl,
			end if #if (Sponsoring_Top_Level_Account_ID == "")
		end if  #(element_exists(Hierarchy_Definition_tbl,Sponsoring_Account_ID))
	end if     #if Sponsoring_Account_ID != ""

	next state Account_Manager

	if HM_RTDB_Key != ""
	then
		# payment type is "3" with BR Account	
		next event HM_RTDB_Retrieve
		return
	else
		# payment type is "2" with sponsoring account
		next event Determine_Hierarchy_Complete
		return
	end if

end event P_S!Request_Hierarchy_Information

#------------------------------------------------------------------------------
#Event          P_S!Request_Group_Information
#
#Description    Use Account ID1 to search centralized group data,get group list
#               for Account ID1, if Group list length exceed 3000, the rest group 
#               omitted. increase Number of Successful cDB Accesses.
#		Add by VFCZ Feature 70577
#------------------------------------------------------------------------------
event P_S!Request_Group_Information
dynamic
	Local_Group_IDs				string
	Local_Temp_String			string
	Local_Next_String			string
	Local_BR_String				string
	Local_Branch_ID				string
	Local_BR_Has_Found			flag
	Local_Top_Has_Found			flag
	Local_Branch_Number			counter
end dynamic
	#SP28.11 VFQ F74754
	set Online_Hierarchy_Flag = Online_Hierarchy
	set Inter_eCS_COMM_FSM_Call_Index = @.Call_Index
	set Req_Group_Info_Account_ID1 = @.Account_ID1 : ":"
	reset S_P!Request_Group_Information_Result
	incr Glb_Service_Measurement_Rec.Number_of_Successful_cDB_Accesses
	
	# SP28.14 75195
	if cDB_RTDB_Enabled
	then	
		
		if !Online_Hierarchy_Flag
		then
			set Retrieve_CD_RTDB_Step = P_S_Req_Group_Info
			set Request_CDB_RTDB_Retrieve.key_index = Req_Group_Info_Account_ID1
			set CDB_RTDB_Max_Records = Glb_Group_IDs_Max_Length
			reset RTDB_Exact_Match
			next event Request_CDB_RTDB_Retrieve
			return
		else
			reset Group_ID_Pos
			reset Group_ID_List_tbl[]
			reset Branch_Number
			reset Top_Has_Found
			reset BR_Has_Found
			reset BR_String
			reset Next_String
			set Retrieve_CD_RTDB_Step = P_S_Req_Group_Info_Online
			set Request_CDB_RTDB_Retrieve.key_index = Req_Group_Info_Account_ID1
			set CDB_RTDB_Max_Records = Glb_Group_IDs_Max_Length
			reset RTDB_Exact_Match
			next event Request_CDB_RTDB_Retrieve
			return
		end if

	end if

	test prefix_matches(Centralized_Group_tbl, Req_Group_Info_Account_ID1)
	case e_prefix_no_match
		reset Local_Group_IDs
	other
		if !Online_Hierarchy_Flag
		then
			set Glb_Temp_String1 = index_next(Centralized_Group_tbl, Req_Group_Info_Account_ID1)
			Parse_Object(":", Glb_Temp_String1)
			set Glb_Parsed = Glb_Parsed : ":"
			while Glb_Parsed == Req_Group_Info_Account_ID1
			do
				set Local_Temp_String = Local_Group_IDs : Glb_Remainder : ","
				if length(Local_Temp_String) > Glb_Group_IDs_Max_Length
				then
					set S_P!Request_Group_Information_Result.Length_Limit_Exceed
					exit while
				end if
				set Local_Group_IDs = Local_Group_IDs : Glb_Remainder : ","
				set Glb_Temp_String1 = index_next(Centralized_Group_tbl, Glb_Temp_String1)
				Parse_Object(":", Glb_Temp_String1)
				set Glb_Parsed = Glb_Parsed : ":"
			end while
		else	    	
			set Glb_Temp_String1 = Req_Group_Info_Account_ID1
			set Glb_Temp_String1 = index_next(Centralized_Group_tbl, Glb_Temp_String1)
			Parse_Object(":", Glb_Temp_String1)

			while Glb_Parsed == @.Account_ID1 && Glb_Remainder != ""
			do							
				set Local_Branch_ID = Glb_Remainder

				incr Local_Branch_Number
				reset Local_Top_Has_Found
				reset Local_BR_Has_Found

				set Local_Temp_String = Local_Group_IDs : "H" : string(Local_Branch_Number) : "="

				while !Local_Top_Has_Found
				do		     		
					set Centralized_Group_tbl.index = Glb_Parsed : ":" : Glb_Remainder
					if !Local_BR_Has_Found &&
						Centralized_Group_tbl.Billing_Responsibility_Indicator
					then
						set Local_BR_Has_Found
						set Local_BR_String = ",BR=" : Glb_Remainder
					end if

					if Centralized_Group_tbl.Top_Account_Indicator
					then
						set Local_Top_Has_Found
						if Local_BR_Has_Found
						then
							set Local_Next_String = Glb_Remainder : Local_BR_String : ";"
						else
							set Local_Next_String = Glb_Remainder : ";"
						end if							
					else
						set Local_Next_String = Glb_Remainder : ":"
					end if

					set Local_Temp_String = Local_Temp_String : Local_Next_String

					if Local_Top_Has_Found
					then
						exit while
					else
						set Glb_Temp_String2 = Glb_Remainder
						set Glb_Temp_String1 = Glb_Remainder : ":"
						set Glb_Temp_String1
							= index_next(Centralized_Group_tbl, Glb_Temp_String1)
						Parse_Object(":", Glb_Temp_String1)

						if Glb_Temp_String2 != Glb_Parsed || Glb_Remainder == ""
						then
							set Local_Top_Has_Found
							set Local_Temp_String =
								substring(Local_Temp_String, 1, length(Local_Temp_String) - 1)
							if Local_BR_Has_Found
							then
								set Local_Temp_String = Local_Temp_String : Local_BR_String : ";"
							else
								set Local_Temp_String = Local_Temp_String : ";"
							end if
						end if 		  
					end if		       
				end while

				if length(Local_Temp_String) > Glb_Group_IDs_Max_Length
				then
					set S_P!Request_Group_Information_Result.Length_Limit_Exceed
					exit while
				else
					set Local_Group_IDs = Local_Temp_String
				end if 

				set Glb_Temp_String1 = Req_Group_Info_Account_ID1 : Local_Branch_ID
				set Glb_Temp_String1 = index_next(Centralized_Group_tbl, Glb_Temp_String1)
				Parse_Object(":", Glb_Temp_String1)
			end while
		end if

	end test
	# remove the last "," 
	if Local_Group_IDs != ""
	then
		set Local_Group_IDs = substring(Local_Group_IDs, 1, length(Local_Group_IDs) - 1)
	end if
	set S_P!Request_Group_Information_Result.Account_List = Local_Group_IDs
	send(to = Inter_eCS_COMM_FSM_Call_Index,
		event = S_P!Request_Group_Information_Result,
		ack = false)
	next event Service_Terminate_Call
end event P_S!Request_Group_Information
# VzW 72139
#------------------------------------------------------------------------------
#Event          P_S!Upd_Counter_Bro_Para
#
#Description	In this event we use member id or group id to query GPRSSIM then 
#		get the location of the member or group
#------------------------------------------------------------------------------
event P_S!Upd_Counter_Bro_Para
	set Glb_Temp_Counter_1 = Glb_Hung_Call_Timer 
	limit(call_timeout = Glb_Temp_Counter_1)
	#73178 for key mapping, read the Common_Par_tbl
	if @.ID_Type == "G"
	then 	
		if element_exists(Common_Par_tbl, Glb_GSL_SCP_Name)
		then
			set Common_Par_tbl.index = Glb_GSL_SCP_Name
			set Account_Id_Keymap_Plan = Common_Par_tbl.Account_ID_Keymap
		end if
	end if		

	set Upd_Counter_Broadcast_Flag
	set Member_Group_ID = @.ID
	set Member_Group_ID_Type = @.ID_Type
	set LDAP_Temp_String = @.LDAP_String
	set Inter_eCS_COMM_FSM_Call_Index = @.Call_Index

	reset GPRSSIM_Retrieve
	set GPRSSIM_Retrieve.Key_Index = @.ID
	set Retrieve_GPRSSIM_For = RGR_Index_Data_Query_Self_Learning
	next event GPRSSIM_Retrieve
	return

end event P_S!Upd_Counter_Bro_Para
event call!timeout
	set Glb_Temp_Counter_1 = 0
	limit(call_timeout = Glb_Temp_Counter_1)
	#set Glb_Temp_Flag_1 = show_history(call_index())
	next event Service_Terminate_Call
end event call!timeout

# SP28.5 72113  wenbiazh
#------------------------------------------------------------------------------
#Event          P_S!Request_Index_Service 
#
#Description    Deal with "req_idx" dataview, when "OP=Q",  in order to support	
#		self-learning/healing 	
#------------------------------------------------------------------------------
event P_S!Request_Index_Service
	set Glb_Temp_Counter_1 = Glb_Hung_Call_Timer 
	limit(call_timeout = Glb_Temp_Counter_1)
	set Inter_eCS_COMM_FSM_Call_Index = @.Call_Index
	set Request_Index_Service_Parameter_rec.ID = @.ID
	set Request_Index_Service_Parameter_rec.ID_Type = @.ID_Type
	set Request_Index_Service_Parameter_rec.SrvType = @.SrvType
	set Request_Index_Service_Parameter_rec.OP = @.OP
	#SP28.7 VzW 73254
	set Request_Index_Service_Parameter_rec.Ind = @.Ind
	if @.OP == "" || @.OP == "0"
	then
	        #73494 
                set Index_Queries	
                if @.ID_Type == any("S", "") && @.Ind != "Y" || @.ID_Type == "G"
		then
			if @.ID_Type == "S"
			then
				set First_GPRSSIM_Read #73254
			end if
			set Retrieve_GPRSSIM_For = RGR_Index_Data_Query
			set GPRSSIM_Retrieve.Key_Index = @.ID
			next event GPRSSIM_Retrieve
			return
		elif @.ID_Type == "N" || @.Ind == "Y" #73254
		then
			set RTDB_Op_For = Index_Data_Query
			set ID2MDN_RTDB_Retrieve.Key_Index = @.ID
			next event ID2MDN_RTDB_Retrieve
			return
		end if
	elif @.OP == "1"
	then
		if @.ID_Type == any("S", "") && @.Ind != "Y" || @.ID_Type == "G"
		then
			if @.ID_Type == "S"
			then
				set First_GPRSSIM_Read #73254
			end if

			set Retrieve_GPRSSIM_For = RGR_Index_Data_Query_Self_Learning
			set GPRSSIM_Retrieve.Key_Index = @.ID
			next event GPRSSIM_Retrieve
			return
		elif @.ID_Type == "N" || @.Ind == "Y" #73254
		then
			set RTDB_Op_For = Index_Data_Query_Self_Learning
			set ID2MDN_RTDB_Retrieve.Key_Index = @.ID
			next event ID2MDN_RTDB_Retrieve
			return
		else
			reset Send_Request_Index_Service_Response
			set Send_Request_Index_Service_Response.resultcode = "01"
			next event Send_Request_Index_Service_Response
			return
		end if
	elif @.OP == "2"
	then
		if Glb_IDX_QRY_FSM_Customer_Index == 0
		then
			reset Send_Request_Index_Service_Response
			set Send_Request_Index_Service_Response.resultcode = "99"
			next event Send_Request_Index_Service_Response
			return
		end if
		set Request_Self_Learning_Healing.Customer_Call_ID = call_index()
		set Request_Self_Learning_Healing.ID = Request_Index_Service_Parameter_rec.ID
		set Request_Self_Learning_Healing.ID_Type = Request_Index_Service_Parameter_rec.ID_Type
	        set Request_Self_Learning_Healing.Learning_Healing_Type = Self_Healing	
                set Req_SA_To_IQRY_Sending_Flag
		send(to = Glb_IDX_QRY_FSM_Customer_Index,
			event = Request_Self_Learning_Healing,
			ack = true)
		return
	else
		next event Service_Terminate_Call
	end if
end event P_S!Request_Index_Service

# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------
event send_completed
dynamic
        Local_LDAP_Timer			counter
end dynamic
	if Req_SA_To_IQRY_Sending_Flag
	then
	        set Local_LDAP_Timer = Index_Query_Timer
		#SP28.13 VzW 75145
                if Timer_In_1Percent_Second
                then
                        if Local_LDAP_Timer == 0
                        then
                                set Local_LDAP_Timer = 400
                        end if
                        timer!start(ticks = Local_LDAP_Timer + 300)
                        return
                else
                        if Local_LDAP_Timer == 0
                        then
                              set Local_LDAP_Timer = 40
                        end if
                        timer!start(duration = Local_LDAP_Timer / 10 + 3)
                        return
                end if
	end if
	next event Service_Terminate_Call
end event	send_completed

# SP28.5 72113 wenbiazh
#------------------------------------------------------------------------------
event send_failed
	if Req_SA_To_IQRY_Sending_Flag
	then
		reset Send_Request_Index_Service_Response
		set Send_Request_Index_Service_Response.resultcode = "99"
		next event Send_Request_Index_Service_Response
		return
	end if
	next event Service_Terminate_Call
end event	send_failed

# SP28.5 72113  wenbiazh
#------------------------------------------------------------------------------
#Event  	Request_Index_Service_Result
#
#Description    Interface with fsm IDX_QRY_FSM, when IDX_QRY_FSM  get Host info,
#		it will retrun the information of the host  through this event 
#------------------------------------------------------------------------------
event Request_Index_Service_Result
	timer!stop()
	if @.Result_Code == "00"
	then
		if Upd_Counter_Broadcast_Flag #VzW Feature 72139
		then
			reset Update_GPRSSIM_Rec
			set Need_To_Update_Local_DB
			set Update_GPRSSIM_Rec.MDN = @.MDN
			set Update_GPRSSIM_Rec.SCP_Name = @.SCP_Name
			set Update_GPRSSIM_Rec.IMSI1 = @.IMSI1
			set Update_GPRSSIM_Rec.COSP_ID = @.COSP_ID
			set Update_GPRSSIM_Rec.Provider_ID = @.Provider_ID
			set Update_GPRSSIM_Rec.State = @.State
			set Member_SCP_Name = @.SCP_Name
			next event Upd_Counter_Bro_Para
			return
		end if

		reset Send_Request_Index_Service_Response
		set Send_Request_Index_Service_Response.resultcode = "00"
		set Send_Request_Index_Service_Response.MDN = @.MDN
		set Send_Request_Index_Service_Response.SCP_Name = @.SCP_Name
		set Send_Request_Index_Service_Response.IMSI1 = @.IMSI1
		set Send_Request_Index_Service_Response.COSP_ID = @.COSP_ID
		set Send_Request_Index_Service_Response.Provider_ID = @.Provider_ID
		set Send_Request_Index_Service_Response.State = @.State
		# SP28.5 Vzw 72544
		set Send_Request_Index_Service_Response.Alternative_SCP = @.Alternative_SCP
		set Send_Request_Index_Service_Response.Service_Type = @.Service_Type
		set Send_Request_Index_Service_Response.A_IMSI1 = @.A_IMSI1
		#SP28.7 VzW 73254
		set Send_Request_Index_Service_Response.E_IMSI1 = @.E_IMSI1
		set Send_Request_Index_Service_Response.E_IMSI2 = @.E_IMSI2
		set Send_Request_Index_Service_Response.UA = @.UA
		set Send_Request_Index_Service_Response.A_E_IMSI1 = @.A_E_IMSI1
		set Send_Request_Index_Service_Response.A_E_IMSI2 = @.A_E_IMSI2
		set Send_Request_Index_Service_Response.A_UA = @.A_UA

		set Need_To_Update_Local_DB
		next event Send_Request_Index_Service_Response
		return
	else  
	        #R28.7 73494
                if Self_Learning_Blocked_List_Interval > 0 
                         && !SLTBL_RTDB_Updated_Flag
                           && !Suppressed_SelfL_For_PreFaild_flag 
                then
                       if !SLTBL_RTDB_Retrieve_Flag
                       then
                              set SLTBL_RTDB_Retrieve_For_SelfH 
                              set SLTBL_RTDB_Retrieve_Flag
                              if Upd_Counter_Broadcast_Flag
                              then
                                    set SLTBL_RTDB_Retrieve.Key_Index = Member_Group_ID
                              else
                                    set SLTBL_RTDB_Retrieve.Key_Index = Request_Index_Service_Parameter_rec.ID
                              end if 
                              next event SLTBL_RTDB_Retrieve
                              return       
                       end if 
                       set SLTBL_RTDB_Updated_Flag 
                       set SLTBL_RTDB_Record1.Self_Learning_Failure_Timestamp = Counter_Current_Clock  
                       if SLTBL_Record_Found                  
                       then 
                              set SLTBL_RTDB_Flag.Self_Learning_Failure_Timestamp                                        
                              next event SLTBL_RTDB_Replace
                              return                
                       else                    
                              if Upd_Counter_Broadcast_Flag
                              then
                                    set SLTBL_RTDB_Record1.Account_ID = Member_Group_ID
                              else
                                    set SLTBL_RTDB_Record1.Account_ID = Request_Index_Service_Parameter_rec.ID
                              end if  
                              next event SLTBL_RTDB_Insert
                              return                
                       end if
                end if		
                if Upd_Counter_Broadcast_Flag #VzW Feature 72139
		then
			#_add_in_73582 add logic for "02"
			if @.Result_Code == "02"
			then
				set Upd_Counter_Bro_Para_Result.Result_Code = GRC_Not_Find
			else
				set Upd_Counter_Bro_Para_Result.Result_Code = GRC_Failed
			end if
			next event Upd_Counter_Bro_Para_Result
			return
		end if

		reset Send_Request_Index_Service_Response
		set Send_Request_Index_Service_Response.resultcode = @.Result_Code
		next event Send_Request_Index_Service_Response
		return
	end if 
end event Request_Index_Service_Result

# SP28.5 72113  wenbiazh
#------------------------------------------------------------------------------
event time_out
	if Req_SA_To_IQRY_Sending_Flag
	then
		reset Send_Request_Index_Service_Response
		set Send_Request_Index_Service_Response.resultcode = "99"
		next event Send_Request_Index_Service_Response
		return
	end if
	next event Service_Terminate_Call
end event time_out

# SP28.5 72113  wenbiazh
#------------------------------------------------------------------------------
#Event  	Send_Request_Index_Service_Response
#
#Description    send response of req_idx to protocal layer 
#------------------------------------------------------------------------------
event Send_Request_Index_Service_Response
	reset S_P!Request_Index_Service_Result
	if @.resultcode != "00"
	then
		set S_P!Request_Index_Service_Result.result_code = @.resultcode
		send(to = Inter_eCS_COMM_FSM_Call_Index,
			event = S_P!Request_Index_Service_Result,
			ack = false)
		if Request_Index_Service_Parameter_rec.OP == "2" && @.resultcode == "02"
		then
			##ih_cr33608
			set RTDB_Op_For = Index_Data_Query_Self_Healing_Return02_Read_ID2MDN
			set ID2MDN_RTDB_Retrieve.Key_Index = Request_Index_Service_Parameter_rec.ID
			next event ID2MDN_RTDB_Retrieve
			return
		end if
		next event Service_Terminate_Call
		return
	else
		# SP28.5 Vzw 72544
		if @.SCP_Name != ""
		then
			set S_P!Request_Index_Service_Result.return_data = "MDN=" : @.MDN : ",SCP_Name=" : @.SCP_Name
		elif @.Alternative_SCP != ""
		then
			set S_P!Request_Index_Service_Result.return_data = "MDN=" : @.MDN : ",SCP_Name=" : @.Alternative_SCP
		end if

		if @.IMSI1 != ""
		then
			set S_P!Request_Index_Service_Result.return_data = S_P!Request_Index_Service_Result.return_data : ",IMSI1=" : @.IMSI1
		elif @.A_IMSI1 != ""
		then
			set S_P!Request_Index_Service_Result.return_data = S_P!Request_Index_Service_Result.return_data : ",IMSI1=" : @.A_IMSI1
		end if 
		if @.COSP_ID != ""
		then
			set S_P!Request_Index_Service_Result.return_data = S_P!Request_Index_Service_Result.return_data : ",COSP_ID=" : @.COSP_ID
		end if
		if @.Provider_ID != ""
		then
			set S_P!Request_Index_Service_Result.return_data = S_P!Request_Index_Service_Result.return_data : ",Provider_ID=" : @.Provider_ID
		end if
		if @.State != ""
		then
			set S_P!Request_Index_Service_Result.return_data = S_P!Request_Index_Service_Result.return_data : ",State=" : @.State
		end if
		if @.TP != ""
		then
			set S_P!Request_Index_Service_Result.return_data = S_P!Request_Index_Service_Result.return_data : ",TP=" : @.TP
		end if
		# SP28.5 Vzw 72544
		if @.Alternative_SCP != "" && @.SCP_Name != ""
		then
			set S_P!Request_Index_Service_Result.return_data = S_P!Request_Index_Service_Result.return_data : ",Alternative_SCP=" : @.Alternative_SCP
		end if
		set S_P!Request_Index_Service_Result.return_data = S_P!Request_Index_Service_Result.return_data : ",Service_Type=" : string(@.Service_Type)
		#SP28.7 VzW 73254
		if @.UA != ""
		then
			set S_P!Request_Index_Service_Result.return_data =
				S_P!Request_Index_Service_Result.return_data : ",UA=" : @.UA
		elif @.A_UA != ""
		then
			set S_P!Request_Index_Service_Result.return_data =
				S_P!Request_Index_Service_Result.return_data : ",UA=" : @.A_UA
		end if

		set S_P!Request_Index_Service_Result.result_code = @.resultcode
		send(to = Inter_eCS_COMM_FSM_Call_Index,
			event = S_P!Request_Index_Service_Result,
			ack = false)
		if Need_To_Update_Local_DB
		then
			reset I_Sync_Index_Data_With_OCS
			set I_Sync_Index_Data_With_OCS.OP = "3"
			set I_Sync_Index_Data_With_OCS.MDN = @.MDN
			# SP28.5 Vzw 72544
			if Number_Of_Collected_Index_Data == 1
			then
				set I_Sync_Index_Data_With_OCS.SCP_Name = @.SCP_Name
				set I_Sync_Index_Data_With_OCS.IMSI_1 = @.IMSI1
				set I_Sync_Index_Data_With_OCS.COSP_ID = @.COSP_ID
				set I_Sync_Index_Data_With_OCS.Provider_ID = @.Provider_ID
				set I_Sync_Index_Data_With_OCS.State = @.State
				#SP28.7 VzW 73254
				set I_Sync_Index_Data_With_OCS.Extended_IMSI1 = @.E_IMSI1
				set I_Sync_Index_Data_With_OCS.Extended_IMSI2 = @.E_IMSI2
				set I_Sync_Index_Data_With_OCS.UA = @.UA
			elif @.SCP_Name != ""
			then
				set Need_Sync_ASCP_Flag
				set I_Sync_Index_Data_With_OCS.SCP_Name = @.SCP_Name
				set I_Sync_Index_Data_With_OCS.IMSI_1 = @.IMSI1
				#SP28.7 VzW 73254
				set I_Sync_Index_Data_With_OCS.Extended_IMSI1 = @.E_IMSI1
				set I_Sync_Index_Data_With_OCS.Extended_IMSI2 = @.E_IMSI2
				set I_Sync_Index_Data_With_OCS.UA = @.UA

				# need store A_SCP_Name and Service_Type
				set Alternative_SCP_Info.SCP_Name = @.Alternative_SCP
				set Alternative_SCP_Info.Service_Type = @.Service_Type
				set Alternative_SCP_Info.IMSI1 = @.A_IMSI1
				#SP28.7 VzW 73254
				set Alternative_SCP_Info.E_IMSI1 = @.A_E_IMSI1
				set Alternative_SCP_Info.E_IMSI2 = @.A_E_IMSI2
				set Alternative_SCP_Info.UA = @.A_UA

			elif @.Alternative_SCP != ""
			then
				set I_Sync_Index_Data_With_OCS.SCP_Name = @.Alternative_SCP
				set I_Sync_Index_Data_With_OCS.Service_Type = @.Service_Type
				set I_Sync_Index_Data_With_OCS.IMSI_1 = @.A_IMSI1
				set I_Sync_Index_Data_With_OCS.Is_ASCP
				#SP28.7 VzW 73254
				set I_Sync_Index_Data_With_OCS.Extended_IMSI1 = @.A_E_IMSI1
				set I_Sync_Index_Data_With_OCS.Extended_IMSI2 = @.A_E_IMSI2
				set I_Sync_Index_Data_With_OCS.UA = @.A_UA

			end if

			next event I_Sync_Index_Data_With_OCS
			return
		end if
		next event Service_Terminate_Call
		return
	end if
end event Send_Request_Index_Service_Response

# SP28.5 72139
#------------------------------------------------------------------------------
#Event  	Send_Upd_Counter_Bro_Para_Res
#
#Description    send response of req_idx to protocal layer 
#------------------------------------------------------------------------------
event Send_Upd_Counter_Bro_Para_Res

	reset S_P!Upd_Counter_Bro_Para_Result
	set S_P!Upd_Counter_Bro_Para_Result.Result_Code = @.Result_Code
	set S_P!Upd_Counter_Bro_Para_Result.LDAP_String = LDAP_Res_String
	send(to = Inter_eCS_COMM_FSM_Call_Index,
		event = S_P!Upd_Counter_Bro_Para_Result,
		ack = false)
	if Need_To_Update_Local_DB
	then
		reset Need_To_Update_Local_DB
		reset I_Sync_Index_Data_With_OCS
		set I_Sync_Index_Data_With_OCS.OP = "3"
		set I_Sync_Index_Data_With_OCS.MDN = Update_GPRSSIM_Rec.MDN
		set I_Sync_Index_Data_With_OCS.SCP_Name = Update_GPRSSIM_Rec.SCP_Name
		set I_Sync_Index_Data_With_OCS.IMSI_1 = Update_GPRSSIM_Rec.IMSI1
		set I_Sync_Index_Data_With_OCS.COSP_ID = Update_GPRSSIM_Rec.COSP_ID
		set I_Sync_Index_Data_With_OCS.Provider_ID = Update_GPRSSIM_Rec.Provider_ID
		set I_Sync_Index_Data_With_OCS.State = Update_GPRSSIM_Rec.State
		next event I_Sync_Index_Data_With_OCS
		return
	end if
	next event Service_Terminate_Call
	return

end event Send_Upd_Counter_Bro_Para_Res

#------------------------------------------------------------------------------	
#Event		HM_RTDB_Retrieve
#
#Description	This event is used to initiate an RTDB retrieve	on a specified	
#		RTDB, with a specified key and record name as its parameters.
#		This event will	return an result event called HM_Retrieve_Result.
#------------------------------------------------------------------------------	
event HM_RTDB_Retrieve
	#detecting if the read opration	is completed
	reset HM_RTDB_Record1

	if(!Glb_HM_RTDB_Attached)
	then 
		send_om(
	                msg_id = counter("30" : "305"),  #SP28.16 RDAF729606
			msg_class = GSL_Internal_Assert_Message_Class,
			poa = GSL_Internal_Assert_Priority,
			title = "REPT INTERNAL ASSERT=305, SPA=EPPSM",
			message = "Intenal System Error - RTDB operation failed, RTDB Name = " : Glb_HM_RTDB_Table : ".",
			message2 =
			"\nSubscriber ID = " : HM_RTDB_Key :
			"\nCall Instance ID = " : string(call_index()) :
			"\nScenario Location = HM_RTDB_Retrieve"
			)
		set Return_Result = HR_HM_RTDB_Failure
		next event Determine_Hierarchy_Complete
		return
	end if

	#add for the situation that the key is blank
	if(HM_RTDB_Key == "")
	then
		reset HM_Retrieve_Result.success
		set HM_Retrieve_Result.tuple_not_found
		next event HM_Retrieve_Result
		return
	end if

	#Read the account id information
	if Glb_HM_RTDB_In_Memory
	then
		set HM_RTDB_Record1
			= HM_RTDB!read_immediate(Glb_HM_RTDB_Instance, HM_RTDB_Key)
		#Account id is exist
		if(HM_RTDB_Record1.Subscriber_Account_ID != "")
		then
			set HM_Retrieve_Result.success
			reset HM_Retrieve_Result.tuple_not_found
		else
			reset HM_Retrieve_Result.success
			set HM_Retrieve_Result.tuple_not_found
		end if

		next event HM_Retrieve_Result
		return
	else
		HM_RTDB!read(instance = Glb_HM_RTDB_Instance,
			Subscriber_Account_ID = HM_RTDB_Key)
	end if
end event HM_RTDB_Retrieve

#------------------------------------------------------------------------------	
# Event:	HM_Retrieve_Result
#
# Description:	This event will	dispatch the result of HM RTDB read operation
#------------------------------------------------------------------------------	
event HM_Retrieve_Result
	if @.success
	then
		test Retrieve_HM_RTDB_Step
		case DH_Step_Get_Primary_Account_Inf
			set HM_Retrieve_Result_Primary_Account.success
			next event HM_Retrieve_Result_Primary_Account
			return
		case DH_Step_Get_Secondary_Account_Inf
			set HM_Retrieve_Result_Secondary_Account.success
			next event HM_Retrieve_Result_Secondary_Account
			return
		other
			next event Service_Non_Fatal_Error
			return
		end test
	elif @.tuple_not_found
	then
		test Retrieve_HM_RTDB_Step
		case DH_Step_Get_Primary_Account_Inf
			set Return_Result = HR_Wrong_Hierarchy_Information
			next event Determine_Hierarchy_Complete
			return
		case DH_Step_Get_Secondary_Account_Inf
			reset HM_Retrieve_Result_Secondary_Account.success
			next event HM_Retrieve_Result_Secondary_Account
			return
		other
			next event Service_Non_Fatal_Error
			return
		end test
		#The RTDB read error, will respond to the request with a failure response
	else
		set Return_Result = HR_HM_RTDB_Failure
		next event Determine_Hierarchy_Complete
	end if
end event HM_Retrieve_Result

#------------------------------------------------------------------------------	
# Event:	Service_Non_Fatal_Error	
#
# Description:	This event is for fatal	error.
#------------------------------------------------------------------------------	
event Service_Non_Fatal_Error
	next event Determine_Hierarchy_Complete
	return
end event Service_Non_Fatal_Error

#------------------------------------------------------------------------------	
# Event:	HM_Retrieve_Result_Primary_Account
#
# Description:	This event is handling the logic after obtain the primary account
#		information. 
#------------------------------------------------------------------------------	
event HM_Retrieve_Result_Primary_Account
	if(@.success)
	then
		set Cur_Depart_Level_Account = HM_RTDB_Record1.Master_Account_ID
		set Master_Account_ID = HM_RTDB_Record1.Master_Account_ID

		#check its legitimacy, can't find in the HD table
		if(Cur_Depart_Level_Account == "")
		then
			set Return_Result = HR_Wrong_Hierarchy_Information
			next event Determine_Hierarchy_Complete
			return
		end if

		if(element_exists(Hierarchy_Definition_tbl,
			Cur_Depart_Level_Account))
		then
			set Hierarchy_Definition_tbl.index
				= Cur_Depart_Level_Account
			set Cur_Company_Level_Account
				= Hierarchy_Definition_tbl.Next_Level_Account_ID

			#check its legitimacy, if the Cur_Company_Level_Account
			#is not exist in the HD table, then it will be think as
			#insufficient levels, so we think it's the top level.
			if(Cur_Company_Level_Account == "")
			then
				#For the Company_Level_Account is "",
				# so the depart_level_account is the top level account
				test Hierarchy_Definition_tbl.Billing_Responsibility_Level
				case 0
					#Special definition for the case: top lever is 0,
					# no Billing_Responsibility_Account_ID in the Hierarchy, 
					# but perhaps share the discount
					set Billing_Responsibility_Account_ID = ""
				case 1
					set Billing_Responsibility_Account_ID
						= Cur_Depart_Level_Account
					set Cur_BR_Level = "1"
				other
					set Billing_Responsibility_Account_ID = ""
				end test

				#read completed, then the next step
				set HM_RTDB_Key = Secondary_Account_ID
				set Retrieve_HM_RTDB_Step
					= DH_Step_Get_Secondary_Account_Inf

				next event HM_RTDB_Retrieve
				return
			end if

			if(element_exists(Hierarchy_Definition_tbl,
				Cur_Company_Level_Account))
			then
				set Hierarchy_Definition_tbl.index
					= Cur_Company_Level_Account

				#maybe delete in the future, in V1035, only support 2 level
				if(Hierarchy_Definition_tbl.Next_Level_Account_ID != "")
				then
					set Return_Result = HR_Wrong_Hierarchy_Information
					next event Determine_Hierarchy_Complete
					return
				end if

				test Hierarchy_Definition_tbl.Billing_Responsibility_Level
				case 0
					#Special definition for the case: top lever is 0,
					# no Billing_Responsibility_Account_ID in the Hierarchy, 
					# but perhaps share the discount
					set Billing_Responsibility_Account_ID = ""
				case 1
					set Billing_Responsibility_Account_ID
						= Cur_Company_Level_Account
					set Cur_BR_Level = "1"
				case 2
					set Billing_Responsibility_Account_ID
						= Cur_Depart_Level_Account
					set Cur_BR_Level = "2"
				other
					set Billing_Responsibility_Account_ID = ""
				end test
				#read completed, then the next step
				set HM_RTDB_Key = Secondary_Account_ID
				set Retrieve_HM_RTDB_Step
					= DH_Step_Get_Secondary_Account_Inf
				next event HM_RTDB_Retrieve
				return
			end if
		end if
	end if		
	set Return_Result = HR_Wrong_Hierarchy_Information
	next event Determine_Hierarchy_Complete
	return
end event HM_Retrieve_Result_Primary_Account
#------------------------------------------------------------------------------	
# Event:	HM_Retrieve_Result_Secondary_Account
#
# Description:	This event is handling the logic after obtain the secondary account
#		information. 
#------------------------------------------------------------------------------	
event HM_Retrieve_Result_Secondary_Account

	reset Intra_Hierarchy_Flag
	set Return_Result = HR_Success

	#Secondary account id is not exist
	if(!(@.success))
	then
		next event Determine_Hierarchy_Complete
		return
	else
		if(HM_RTDB_Record1.Master_Account_ID == "")
		then
			reset Intra_Hierarchy_Flag
			next event Determine_Hierarchy_Complete
			return
		end if

		#include the situation that the Cur_Company_Level_Account is null
		#Cur_Depart_Level_Account is not the null for judge before
		if((Cur_Depart_Level_Account == HM_RTDB_Record1.Master_Account_ID)
			|| (Cur_Company_Level_Account == HM_RTDB_Record1.Master_Account_ID))
		then
			set Intra_Hierarchy_Flag
		else
			if(element_exists(Hierarchy_Definition_tbl,
				HM_RTDB_Record1.Master_Account_ID))
			then
				set Hierarchy_Definition_tbl.index =
					HM_RTDB_Record1.Master_Account_ID

				if(Hierarchy_Definition_tbl.Next_Level_Account_ID
					== "")
				then
					reset Intra_Hierarchy_Flag
					next event Determine_Hierarchy_Complete
					return
				end if
				if(Cur_Company_Level_Account
					== Hierarchy_Definition_tbl.Next_Level_Account_ID)
				then
					set Intra_Hierarchy_Flag
				elif((Cur_Company_Level_Account == "") && (Cur_Depart_Level_Account
					== Hierarchy_Definition_tbl.Next_Level_Account_ID))
				then
					set Intra_Hierarchy_Flag
				end if
			end if
		end if

		#read completed, then the next step
		next event Determine_Hierarchy_Complete
		return
	end if
end event HM_Retrieve_Result_Secondary_Account

#------------------------------------------------------------------------------ 
# Event:        Determine_Hierarchy_Complete
#
# Description:  
#------------------------------------------------------------------------------ 
event Determine_Hierarchy_Complete
	# v10.12 65894
	# if both of the account id is null, then no need to query GPRSSIM RTDB
	if Sponsoring_Account_ID == "" && Master_Account_ID == ""
	then
		next event Determine_Hierarchy_Complete_1
		return
	elif Master_Account_ID != ""
	then
		set Retrieve_GPRSSIM_For = RGR_Master_Account
		set GPRSSIM_Retrieve.Key_Index = Master_Account_ID
		next event GPRSSIM_Retrieve
		return
	else # Sponsoring_Account_ID != ""
		set Retrieve_GPRSSIM_For = RGR_Sponsoring_Account
		set GPRSSIM_Retrieve.Key_Index = Sponsoring_Account_ID
		next event GPRSSIM_Retrieve
		return
	end if

end event Determine_Hierarchy_Complete

#------------------------------------------------------------------------------	
# Event:	Determine_Hierarchy_Complete_1
#
# Description:	After the hierarchy logic, the result sent to the fsm
#		Inter_eCS_COMM_FSM as response to the request.
#               Renamed from Determine_Hierarchy_Complete in v10.12 65894
#------------------------------------------------------------------------------	
event Determine_Hierarchy_Complete_1
dynamic
	Local_Branch_Number			counter
	Local_Level_Number			counter
	Local_Total_Level			counter
end dynamic

	reset S_P!Request_Hierarchy_Information_Result
	set S_P!Request_Hierarchy_Information_Result.Master_Account_ID
		= Master_Account_ID
	set S_P!Request_Hierarchy_Information_Result.Intra_Hierarchy_Flag
		= Intra_Hierarchy_Flag
	# SP27.9 VFCZ 70577
	set S_P!Request_Hierarchy_Information_Result.Intra_Group_Indicator
		= Intra_Group_Indicator

	# V10.13 66403
	if Secondary_Account_ID != any("QUYINDEXDB", "QUYCOSP")#QUYCOSP Add by VFGH 69452
		&& Query_Group_Operation != any("0", "1", "2", "3","4")#SP27.9 VFCZ 70577
	then
		# V10.5 62977 spa678628dA
		if Primary_Account_ID != "" &&
			Cur_BR_Level == ""
		then
			set Return_Result = HR_Wrong_Hierarchy_Information
		end if

		if Sponsoring_Account_ID != ""
			&& Return_Result == HR_Success
		then
			if Sponsoring_Hierarchy_Account_Indicator == "" ||
				(Sponsoring_Account_ID == Billing_Responsibility_Account_ID)
			then	
				set Return_Result = HR_Invalid_Sponsoring_Account
			elif Sponsoring_Hierarchy_Account_Indicator == "0"
				&& Sponsoring_MSISDN == ""
			then	
				set Return_Result = HR_No_Sponsoring_MSISDN
			elif Sponsoring_Account_eCS_Name == ""
			then	
				set Return_Result = HR_No_Sponsoring_Account_eCS
			end if
		end if
	end if

	#R28.6 72000
	if Online_Hierarchy_Flag && Query_Group_Operation == any("0", "1", "2", "3")
		&& Total_Account_Number > 0 && table_length(Hierarchy_Structure_tbl) > 0
	then
		reset Glb_Hierarchy_Structure_SPI_tbl[]
		set Local_Branch_Number = 1

		while Local_Branch_Number <= Total_Account_Number
		do
			insert into Glb_Hierarchy_Structure_SPI_tbl at Local_Branch_Number

			set Hierarchy_Structure_tbl.index = Local_Branch_Number
			if Hierarchy_Structure_tbl.present
			then
				set Glb_Hierarchy_Structure_SPI_tbl.relation_level.value =
					Hierarchy_Structure_tbl.Relation_Level
				set Glb_Hierarchy_Structure_SPI_tbl.relation_level.present

				set Glb_Hierarchy_Structure_SPI_tbl.br_level.value = Hierarchy_Structure_tbl.BR_Level
				set Glb_Hierarchy_Structure_SPI_tbl.br_level.present
				if Hierarchy_Structure_tbl.SCP_Name != ""
				then
					set Glb_Hierarchy_Structure_SPI_tbl.scp_name.value =
						Hierarchy_Structure_tbl.SCP_Name
					set Glb_Hierarchy_Structure_SPI_tbl.scp_name.present
				end if
				set Local_Total_Level = Hierarchy_Structure_tbl.Level_Number

				reset Glb_Branch_Acc_List_tbl[]
				set Glb_Branch_Acc_List_tbl[] = Hierarchy_Structure_tbl.Account_List_rec.Account_List_tbl[]

				set Local_Level_Number = 1

				while Local_Level_Number <= Local_Total_Level
				do

					test Local_Level_Number
%%         			for {set i 1} {$i <= 10} {incr i +1} {
					case ${i} set Glb_Hierarchy_Structure_SPI_tbl.primary_hierarchy${i}.value =
							Glb_Branch_Acc_List_tbl[Local_Level_Number].Account_ID
						set Glb_Hierarchy_Structure_SPI_tbl.primary_hierarchy${i}.present
%%				}
					end test

					incr Local_Level_Number

				end while		
			end if

			incr Local_Branch_Number

		end while

	end if

	#R27.7 Inter-spa commu & 3D tool
	if(Save_Qid == 0) || (From_Dest == xp_dest(""))
	then # old logic
		set S_P!Request_Hierarchy_Information_Result.Return_Result
			= Return_Result

		#SP28.6 72000
		if Online_Hierarchy_Flag && Query_Group_Operation == any("0", "1", "2", "3") && Secondary_Account_ID != "QUYINDEXDB" # SP28.9 73335
		then
			reset Glb_Qry_Grp_Host_Name_Rsp_Rec
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.spi_hierarchy_list_rec.present
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.spi_hierarchy_list_rec.hierarchy_list_tbl[]
				= Glb_Hierarchy_Structure_SPI_tbl[]

			set Glb_spi_Encoded_rst =
				spi!encode_query_group_host_name_response_message(spi_protocol_bound, Glb_Qry_Grp_Host_Name_Rsp_Rec)

			if Glb_spi_Encoded_rst.return_code != ire_success
			then
				reset Glb_spi_Encoded_rst.data
				send_om(
	                                msg_id = counter("30" : "201"),  #SP28.16 RDAF729606
					msg_class = GSL_Internal_Assert_Message_Class,
					poa = GSL_Internal_Assert_Priority,
					title = "REPT NETWORK ASSERT=201, SPA=EPPSM",
					message = "Encode Query Group Host Name Response Failed!" :
					"Reason=" : string(Glb_spi_Encoded_rst.return_code),
					message2 = "\nCall Instance ID = " : string(call_index()) :
					"\nScenario Location = Determine_Hierarchy_Complete_1"
					)
			end if
			set S_P!Request_Hierarchy_Information_Result.Account_SCP_List = Glb_spi_Encoded_rst.data
			#SP28.10 72817
			set S_P!Request_Hierarchy_Information_Result.Sponsoring_Account_eCS_Name = Sponsoring_Account_eCS_Name

		else

			# V10SU4 62982 mr=spa676171aA
			set S_P!Request_Hierarchy_Information_Result.Company_Account_ID
				= Cur_Company_Level_Account
			set S_P!Request_Hierarchy_Information_Result.Master_Account_eCS_Name
				= Master_Account_eCS_Name
			set S_P!Request_Hierarchy_Information_Result.BR_Level
				= Cur_BR_Level
			set S_P!Request_Hierarchy_Information_Result.Sponsoring_Account_eCS_Name
				= Sponsoring_Account_eCS_Name
			set S_P!Request_Hierarchy_Information_Result.Sponsoring_Hierarchy_Account_Indicator
				= Sponsoring_Hierarchy_Account_Indicator
			set S_P!Request_Hierarchy_Information_Result.Sponsoring_MSISDN
				= Sponsoring_MSISDN

			# V10.5 62977 spa678628dA
			set S_P!Request_Hierarchy_Information_Result.Sponsoring_Top_Level_Account_ID
				= Sponsoring_Top_Level_Account_ID

			# V10.13 66403
			set S_P!Request_Hierarchy_Information_Result.Account_SCP_List = Account_SCP_List

		end if
		send(to = Inter_eCS_COMM_FSM_Call_Index,
			event = S_P!Request_Hierarchy_Information_Result,
			ack = false)
	else # use iscm
		reset Glb_Qry_Grp_Host_Name_Rsp_Rec
		test Return_Result
		case HR_Success
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.result = 0
		case HR_Wrong_Hierarchy_Information
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.result = 1 #HR_Failer
		case HR_HM_RTDB_Failure
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.result = 2 #HR_Failer
		case HR_Invalid_Sponsoring_Account #V10.5 62977
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.result = 3
		case HR_No_Sponsoring_MSISDN #V10.5 62977
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.result = 4
		case HR_No_Sponsoring_Account_eCS #V10.5 62977
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.result = 5
		other
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.result = 100 #HR_Failer
		end test

		#SP28.6 72000
		if Online_Hierarchy_Flag && Query_Group_Operation == any("0", "1", "2", "3") && Secondary_Account_ID != "QUYINDEXDB" # SP28.9 73335
		then
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.spi_hierarchy_list_rec.present
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.spi_hierarchy_list_rec.hierarchy_list_tbl[]
				= Glb_Hierarchy_Structure_SPI_tbl[]
		else

			set Glb_Qry_Grp_Host_Name_Rsp_Rec.master_account_id = Master_Account_ID
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.company_account_id = Cur_Company_Level_Account
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.br_level = Cur_BR_Level
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.master_accounte_cs_name = Master_Account_eCS_Name
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.intra_hierarchy_flag = Intra_Hierarchy_Flag
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.sponsoring_accounte_cs_name = Sponsoring_Account_eCS_Name
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.sponsoring_hierarchy_account_indicator = Sponsoring_Hierarchy_Account_Indicator
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.sponsoring_msisdn = Sponsoring_MSISDN
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.sponsoring_top_level_account_id = Sponsoring_Top_Level_Account_ID
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.more_account_scp_name = Account_SCP_List
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.intra_group.value = Intra_Group_Indicator # SP27.9 VFCZ 70577
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.intra_group.present

		end if

		#encode the response message and send out
		set Glb_spi_Encoded_rst = spi!encode_query_group_host_name_response_message(spi_protocol_bound, Glb_Qry_Grp_Host_Name_Rsp_Rec)
		if Glb_spi_Encoded_rst.return_code != ire_success
		then
			reset Glb_spi_Encoded_rst.data
			#send_om
			send_om(
	                        msg_id = counter("30" : "201"),  #SP28.16 RDAF729606
				msg_class = GSL_Internal_Assert_Message_Class,
				poa = GSL_Internal_Assert_Priority,
				title = "REPT NETWORK ASSERT=201, SPA=EPPSM",
				message = "Encode Query Group Host Name Response Failed!" :
				"Reason=" : string(Glb_spi_Encoded_rst.return_code),
				message2 = "\nCall Instance ID = " : string(call_index()) :
				"\nScenario Location = Determine_Hierarchy_Complete_1"
				)
		end if
		# the message name add a ! as prefix to indicate the Relay on Lead to end
		iscm!send(routing_type = iscm_one_q_of_qid,
			to_dest = From_Dest,
			save_qid = Save_Qid,
			msg_name = "!FGMrspGHN",
			msg_version = 1,
			payload = Glb_spi_Encoded_rst.data,
			cargo = Glb_InterSPA_cargo_Flag
			)
		return

	end if #if (Save_Qid == 0) || (From_Dest == xp_dest(""))

	next event Service_Terminate_Call
end event Determine_Hierarchy_Complete_1

#--------------------------------------------------------------
# Event: 	CLIINFO_Retrieve_Result
#
# Description:	This event handles the result of retrieve CLIINFO
#		RTDB
#
# Added by:	sp27.7 VFGH feature 69723
#
#--------------------------------------------------------------
event CLIINFO_Retrieve_Result
	test Message_Name_For_InterSPA
	case "CS_CLIINFO_Rtr" # sp27.7 VFGH feature 69723
		# sent retrieve result to ECTRL
		reset Message_For_Ectrl_EPPSM_Rec
		if @.success
		then
			set Message_For_Ectrl_EPPSM_Rec.result_code = "success"
			set Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_record.cli_key
				= CLIINFO_Record1.CLI_Key
			set Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_record.msisdn
				= CLIINFO_Record1.MSISDN
			set Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_record.blocking_timestamp
				= CLIINFO_Record1.Blocking_Timestamp
			set Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_record.first_wrongaccountid_atmp_timestamp
				= CLIINFO_Record1.First_WrongAccountID_Atmp_Timestamp
			set Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_record.wrongaccountid_accum_times
				= CLIINFO_Record1.WrongAccountID_Accum_Times
		elif @.tuple_not_found
		then
			set Message_For_Ectrl_EPPSM_Rec.result_code = "tuple_not_found"
		else
			set Message_For_Ectrl_EPPSM_Rec.result_code = "rtdb_not_attached"
		end if
		next event Send_Info_Back_To_ECTRL
		return
	case any("CLI_All", "CLI_Attach")
		if @.success
		then
			if CLIINFO_Record1.MSISDN == Attach_Detach_MSISDN
			then
				if Message_Name_For_InterSPA == "CLI_All"
				then
					set CLIINFO_Record1.CLI_Key = Attach_Detach_CLI
					reset CLIINFO_Record1.MSISDN
					set CLIINFO_Flag.MSISDN
					set Attach_Detach_RTDB_Next_Operation_Or_Source = Source_From_Detach
					next event CLIINFO_Replace
					return
				else
					set Attach_Detach_RTDB_Next_Operation_Or_Source = Next_Send_To_Ectrl
					set MDNCLI_Record1.MSISDN = Attach_Detach_MSISDN
					set MDNCLI_Record1.CLI = Attach_Detach_CLI
					next event MDNCLI_Insert
					return
				end if
			elif CLIINFO_Record1.MSISDN != ""
			then
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Fail"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "The_CLI_Has_Been_Already_Attached_To_Another_Account"
				next event Send_Info_Back_To_ECTRL
				return
			else
				set Attach_Detach_RTDB_Next_Operation_Or_Source = Next_CLIINFO_Replace
				set MDNCLI_Record1.MSISDN = Attach_Detach_MSISDN
				set MDNCLI_Record1.CLI = Attach_Detach_CLI
				next event MDNCLI_Insert
				return
			end if
		elif @.tuple_not_found
		then
			set Attach_Detach_RTDB_Next_Operation_Or_Source = Next_CLIINFO_Insert
			set MDNCLI_Record1.MSISDN = Attach_Detach_MSISDN
			set MDNCLI_Record1.CLI = Attach_Detach_CLI
			next event MDNCLI_Insert
			return
		else
			if Message_Name_For_InterSPA == "CLI_All"
			then 	
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Failed"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
				next event Send_Info_Back_To_ECTRL
				return
			else
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Fail"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
				next event Send_Info_Back_To_ECTRL
				return
			end if
		end if
	case "CLI_Detach"
		if @.success
		then
			if CLIINFO_Record1.MSISDN == Attach_Detach_MSISDN
			then
				set CLIINFO_Record1.CLI_Key = Attach_Detach_CLI
				reset CLIINFO_Record1.MSISDN
				set CLIINFO_Flag.MSISDN
				next event CLIINFO_Replace
				return
			else
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Detach_Fail"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "Detach_Failure"
				next event Send_Info_Back_To_ECTRL
				return
			end if
		elif @.tuple_not_found
		then
			set Message_For_Ectrl_EPPSM_Rec.result_code = "Detach_Fail"
			set Message_For_Ectrl_EPPSM_Rec.fail_reason = "Detach_Failure"
			next event Send_Info_Back_To_ECTRL
			return
		else
			set Message_For_Ectrl_EPPSM_Rec.result_code = "Detach_Fail"
			set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
			next event Send_Info_Back_To_ECTRL
			return
		end if

	other
		next event Service_Non_Fatal_Error
		return
	end test
end event CLIINFO_Retrieve_Result

#--------------------------------------------------------------
# Event:        CLIINFO_Delete_Result
#
# Description:  This event handles the result of delete CLIINFO
#               RTDB
#
# Added by:     sp27.7 VFGH feature 69723
#
#--------------------------------------------------------------
event CLIINFO_Delete_Result
	test Message_Name_For_InterSPA
	case "CS_CLIINFO_Del" # sp27.7 VFGH feature 69723
		# sent retrieve result to ECTRL
		reset Message_For_Ectrl_EPPSM_Rec
		if @.success
		then
			set Message_For_Ectrl_EPPSM_Rec.result_code = "success"
		end if
		next event Send_Info_Back_To_ECTRL
		return
	other
		next event Service_Non_Fatal_Error
		return
	end test
end event CLIINFO_Delete_Result

#--------------------------------------------------------------
# Event:        CLIINFO_Replace_Result
#
# Description:  This event handles the result of replace CLIINFO
#               RTDB
#
# Added by:     sp27.7 VFGH feature 69723
#
#--------------------------------------------------------------
event CLIINFO_Replace_Result
	test Message_Name_For_InterSPA
	case any("CS_CLIINFO_Rpl", "CLIINFO_Rpl")# sp27.7 VFGH feature 69723
		# sent retrieve result to ECTRL
		reset Message_For_Ectrl_EPPSM_Rec
		next event Send_Info_Back_To_ECTRL
		return
	case any("CLI_All", "CLI_Attach", "CLI_Detach")
		if @.success
		then
			test Message_Name_For_InterSPA
			case "CLI_All"
				if Attach_Detach_RTDB_Next_Operation_Or_Source == Source_From_Attach
				then
					set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Success"
				else 
					set Message_For_Ectrl_EPPSM_Rec.result_code = "Detach_Success"
				end if
				next event Send_Info_Back_To_ECTRL
				return
			case "CLI_Attach"
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Success"
				next event Send_Info_Back_To_ECTRL
				return
			case "CLI_Detach"
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Detach_Success"
				next event Send_Info_Back_To_ECTRL
				return
			end test
		else
			test Message_Name_For_InterSPA
			case "CLI_All"
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Failed"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
				next event Send_Info_Back_To_ECTRL
				return
			case "CLI_Attach"
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Fail"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
				next event Send_Info_Back_To_ECTRL
				return
			case "CLI_Detach"
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Detach_Fail"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
				next event Send_Info_Back_To_ECTRL
				return
			end test
		end if
	other
		next event Service_Non_Fatal_Error
		return
	end test
end event CLIINFO_Replace_Result

#--------------------------------------------------------------
# Event:        CLIINFO_Insert_Result
#
# Description:  This event handles the result of insert CLIINFO
#               RTDB
#
# Added by:     sp27.7 VFGH feature 69723
#
#--------------------------------------------------------------
event CLIINFO_Insert_Result
	test Message_Name_For_InterSPA
	case "CLIINFO_Ins" # sp27.7 VFGH feature 69723
		# sent retrieve result to ECTRL
		reset Message_For_Ectrl_EPPSM_Rec
		next event Send_Info_Back_To_ECTRL
		return
	case any("CLI_All", "CLI_Attach")
		if @.success
		then
			set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Success"
			next event Send_Info_Back_To_ECTRL
			return
		else
			test Message_Name_For_InterSPA
			case "CLI_All"
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Failed"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
				next event Send_Info_Back_To_ECTRL
				return
			case "CLI_Attach"
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Fail"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
				next event Send_Info_Back_To_ECTRL
				return
			end test
		end if
	other
		next event Service_Non_Fatal_Error
		return
	end test
end event CLIINFO_Insert_Result

#--------------------------------------------------------------
# Event:        MDNCLI_Retrieve_Result
#
# Description:  This event handles the result of retrieve MDNCLI
#               RTDB
#
# Added by:     sp27.7 VFGH feature 69723
#
#--------------------------------------------------------------
event MDNCLI_Retrieve_Result
	if @.success
	then
		if MDNCLI_Record1.CLI == Attach_Detach_CLI
		then
			test Message_Name_For_InterSPA
			case "CLI_Attach"
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Fail"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "The_CLI_Has_Been_Already_Attached_To_The_Account"
				next event Send_Info_Back_To_ECTRL
				return
			case any("CLI_All", "CLI_Detach")
				set MDNCLI_Delete.Key_Index = Attach_Detach_MSISDN
				next event MDNCLI_Delete
				return
			end test
		else
			test Message_Name_For_InterSPA
			case any("CLI_All", "CLI_Attach")
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Fail"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "The_Account_Has_Been_Already_Attached_To_Another_CLI"
				next event Send_Info_Back_To_ECTRL
				return
			case "CLI_Detach"
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Detach_Fail"
				set Message_For_Ectrl_EPPSM_Rec.fail_reason = "Detach_Failure"
				next event Send_Info_Back_To_ECTRL
				return
			end test
		end if	
	elif @.tuple_not_found
	then
		test Message_Name_For_InterSPA
		case any("CLI_All", "CLI_Attach", "CLI_Detach")
			set CLIINFO_Retrieve.Key_Index = Attach_Detach_CLI
			next event CLIINFO_Retrieve
			return
		end test
	else
		test Message_Name_For_InterSPA
		case "CLI_Attach"
			set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Fail"
			set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
			next event Send_Info_Back_To_ECTRL
			return
		case "CLI_Detach"
			set Message_For_Ectrl_EPPSM_Rec.result_code = "Detach_Fail"
			set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
			next event Send_Info_Back_To_ECTRL
			return
		case "CLI_All"
			set Message_For_Ectrl_EPPSM_Rec.result_code = "Failed"
			set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
			next event Send_Info_Back_To_ECTRL
			return
		end test
	end if
end event MDNCLI_Retrieve_Result

#--------------------------------------------------------------
# Event:        MDNCLI_Replace_Result
#
# Description:  This event handles the result of replace MDNCLI
#               RTDB
#
# Added by:     sp27.7 VFGH feature 69723
#
#--------------------------------------------------------------
event MDNCLI_Replace_Result

end event MDNCLI_Replace_Result

#--------------------------------------------------------------
# Event:        MDNCLI_Delete_Result
#
# Description:  This event handles the result of delete MDNCLI
#               RTDB
#
# Added by:     sp27.7 VFGH feature 69723
#
#--------------------------------------------------------------
event MDNCLI_Delete_Result
	if @.success
	then
		test Message_Name_For_InterSPA
		case any("CLI_All", "CLI_Detach")
			set CLIINFO_Record1.CLI_Key = Attach_Detach_CLI
			reset CLIINFO_Record1.MSISDN
			set CLIINFO_Flag.MSISDN
			set Attach_Detach_RTDB_Next_Operation_Or_Source = Source_From_Detach
			next event CLIINFO_Replace
			return
		end test
	else
		test Message_Name_For_InterSPA
		case "CLI_Detach"
			set Message_For_Ectrl_EPPSM_Rec.result_code = "Detach_Fail"
			set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
			next event Send_Info_Back_To_ECTRL
			return
		case "CLI_All"
			set Message_For_Ectrl_EPPSM_Rec.result_code = "Failed"
			set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
			next event Send_Info_Back_To_ECTRL
			return
		end test
	end if
end event MDNCLI_Delete_Result

#--------------------------------------------------------------
# Event:        MDNCLI_Insert_Result
#
# Description:  This event handles the result of insert MDNCLI
#               RTDB
#
# Added by:     sp27.7 VFGH feature 69723
#
#--------------------------------------------------------------
event MDNCLI_Insert_Result
	if @.success
	then
		test Message_Name_For_InterSPA
		case any("CLI_Attach", "CLI_All")
			set CLIINFO_Record1.CLI_Key = Attach_Detach_CLI
			set CLIINFO_Record1.MSISDN = Attach_Detach_MSISDN
			test Attach_Detach_RTDB_Next_Operation_Or_Source
			case Next_CLIINFO_Insert
				next event CLIINFO_Insert
				return
			case Next_CLIINFO_Replace
				set Attach_Detach_RTDB_Next_Operation_Or_Source = Source_From_Attach
				set CLIINFO_Flag.MSISDN
				next event CLIINFO_Replace
				return
			case Next_Send_To_Ectrl
				set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Success"
				next event Send_Info_Back_To_ECTRL
				return
			end test
		end test 
	else
		test Message_Name_For_InterSPA
		case "CLI_Attach"
			set Message_For_Ectrl_EPPSM_Rec.result_code = "Attach_Fail"
			set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
			next event Send_Info_Back_To_ECTRL
			return
		case "CLI_All"
			set Message_For_Ectrl_EPPSM_Rec.result_code = "Failed"
			set Message_For_Ectrl_EPPSM_Rec.fail_reason = "RTDB_Operation_Failure"
			next event Send_Info_Back_To_ECTRL
			return
		end test
	end if

end event MDNCLI_Insert_Result

# SP28.8 72933
#--------------------------------------------------------------------------------
# Event: 	P_S!Request_Inter_SPA
#
# Description:	This event receives Inter-SPA request message from LDAP protocol
#		Layer and distribute them to related events.
#		This event is used to instead of event iscm!message_received when
#		using LDAP for Inter-SPA request.
#
#--------------------------------------------------------------------------------
event P_S!Request_Inter_SPA

	set Use_LDAP_For_Inter_SPA_Flag # Indicate "Use LDAP for Inter-SPA" in SERVICE_ADMIN

	set Inter_eCS_COMM_FSM_Call_Index = @.Call_Index

	if @.Msg_N == any("GPRSSIMRtr", "CLI_All", "CLI_Attach", "CLI_Detach",
		"CS_CLIINFO_Rtr", "CS_CLIINFO_Del", "CS_CLIINFO_Rpl",
		"CLIINFO_Rpl", "CLIINFO_Ins")# Inter-SPA request from ECTRL
	then
		set Request_Info_From_ECTRL.Msg_N = @.Msg_N
		set Request_Info_From_ECTRL.Payload = @.Payload
		next event Request_Info_From_ECTRL
		return
	end if

	next event Service_Terminate_Call
	return

end event P_S!Request_Inter_SPA

# SP28.8 72933
#--------------------------------------------------------------------------------
# Event: 	Request_Info_From_ECTRL
#
# Description:	This event is called by P_S!Request_Inter_SPA and iscm!message_received
#		to handle the Inter-SPA request message from ECTRL.
#
#--------------------------------------------------------------------------------
event Request_Info_From_ECTRL
dynamic
	L_Message_Bi_Request_From_ECTRL		spi_ectrl_eppsm_record_dec_bi_return
	#SP28.9 73335
	Local_Account_ID_List_Rec		Account_ID_List_rec
	Local_Length				counter
	#	L_Family_Group_ID_tbl					spi_family_group_id_table
	#end SP28.9 73335
end dynamic

	set Message_Name_For_InterSPA = @.Msg_N

	# Decode the Inter-SPA message
	set L_Message_Bi_Request_From_ECTRL = spi!decode_ectrl_eppsm_record(spi_protocol_bound, @.Payload)

	if L_Message_Bi_Request_From_ECTRL.return_code != ire_success
	then
		set Glb_Temp_String1 = "Decode Message for interSPA failed! -" :
			string(L_Message_Bi_Request_From_ECTRL.return_code)
                #SP28.16 RDAF729606
                Parse_Object(",", string(Glb_Internal_Operation_Assert_Title))
                if Glb_Parse_Temp_Count > 0
                then
                	set Glb_Temp_String_Parsed = map(Glb_Parsed,
                		"abcdefghijklmnopqrstuvwxzyABCDEFGHIJKLMNOPQRSTUVWXYZ= ", "")
                else
                	set Glb_Temp_String_Parsed = "000"
                end if
			
		send_om(
	                msg_id = counter("30" : Glb_Temp_String_Parsed),
			msg_class = GSL_Internal_Assert_Message_Class,
			title = Glb_Internal_Operation_Assert_Title,
			poa = GSL_Internal_Assert_Priority,
			message = "Internal System Error - " : Glb_Temp_String1,
			message2 = "\nCall Instance ID = " : string(call_index()) :
			"\nScenario Location = Request_Info_From_ECTRL"
			)

		if Use_LDAP_For_Inter_SPA_Flag
		then
			# Payload decode error, need to send "01" back to ECTRL
			set InterSPA_Decode_Fail
			next event Send_Info_Back_To_ECTRL
			return
		else
			# Keep old Inter-SPA logic
			set InterSPA_Decode_Fail
			next event Inter_Spa_Error_Handling
			return
		end if
	end if

	# Distribute the Inter-SPA message
	set Message_For_Ectrl_EPPSM_Rec = L_Message_Bi_Request_From_ECTRL.data
	test Message_Name_For_InterSPA
	case "GPRSSIMRtr"
		#SP28.9 73335
		if Message_For_Ectrl_EPPSM_Rec.check_br.value
		then
			set Primary_Account_ID = Message_For_Ectrl_EPPSM_Rec.subscriber_id.value
			set Glb_Family_Group_ID_tbl[] = Message_For_Ectrl_EPPSM_Rec.family_group_id_tbl[]
			reset Account_ID_List_tbl[]
			set Local_Length = 1
			set Total_Account_Number = table_length(Glb_Family_Group_ID_tbl)
			loop Glb_Family_Group_ID_tbl
				set Local_Account_ID_List_Rec.Account_ID = Glb_Family_Group_ID_tbl.family_group_id.value
				insert Local_Account_ID_List_Rec into Account_ID_List_tbl at Local_Length
				incr Local_Length
			end loop Glb_Family_Group_ID_tbl

			set Query_Group_Operation = "2"
			reset Request_Query_Hier_Info
			next event Request_Query_Hier_Info
			return
		end if
		# end SP28.9 73335
		set Retrieve_GPRSSIM_For = RGR_External_Query
		set GPRSSIM_Retrieve.Key_Index = Message_For_Ectrl_EPPSM_Rec.account_id
		next event GPRSSIM_Retrieve
		return
	case any("CLI_All", "CLI_Attach", "CLI_Detach")
		set Attach_Detach_CLI = Message_For_Ectrl_EPPSM_Rec.cli
		set Attach_Detach_MSISDN = Message_For_Ectrl_EPPSM_Rec.account_id
		set MDNCLI_Retrieve.Key_Index = Message_For_Ectrl_EPPSM_Rec.account_id
		reset Message_For_Ectrl_EPPSM_Rec
		set BCI_Account_ID = Message_For_Ectrl_EPPSM_Rec.account_id
		next event MDNCLI_Retrieve
		return
	case "CS_CLIINFO_Rtr"
		set CLIINFO_Retrieve.Key_Index = Message_For_Ectrl_EPPSM_Rec.cli
		next event CLIINFO_Retrieve
		return
	case "CS_CLIINFO_Del"
		set CLIINFO_Delete.Key_Index = Message_For_Ectrl_EPPSM_Rec.cli
		next event CLIINFO_Delete
		return
	case any("CS_CLIINFO_Rpl", "CLIINFO_Rpl", "CLIINFO_Ins")
		set CLIINFO_Record1.CLI_Key = Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_record.cli_key
		set CLIINFO_Record1.MSISDN = Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_record.msisdn
		set CLIINFO_Record1.Blocking_Timestamp =
			Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_record.blocking_timestamp
		set CLIINFO_Record1.First_WrongAccountID_Atmp_Timestamp =
			Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_record.first_wrongaccountid_atmp_timestamp
		set CLIINFO_Record1.WrongAccountID_Accum_Times =
			Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_record.wrongaccountid_accum_times
		if Message_Name_For_InterSPA == "CLIINFO_Ins"
		then
			next event CLIINFO_Insert
			return
		else
			set CLIINFO_Flag.MSISDN =
				Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_flag.msisdn
			set CLIINFO_Flag.Blocking_Timestamp =
				Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_flag.blocking_timestamp
			set CLIINFO_Flag.First_WrongAccountID_Atmp_Timestamp =
				Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_flag.first_wrongaccountid_atmp_timestamp
			set CLIINFO_Flag.WrongAccountID_Accum_Times =
				Message_For_Ectrl_EPPSM_Rec.cliinfo_rtdb_flag.wrongaccountid_accum_times
			next event CLIINFO_Replace
			return
		end if
	end test

	next event Service_Terminate_Call
	return

end event Request_Info_From_ECTRL

#-----------------------------------------------------------
# R27.7 Inter-spa commu & 3D tool test code
#
#
#-----------------------------------------------------------
event iscm!message_received
dynamic
	L_Error_Flag				flag
	L_Account_ID_List_Rec			Account_ID_List_rec
	L_Total_Account_Num			counter
	L_Message_Bi_Request_From_ECTRL		spi_ectrl_eppsm_record_dec_bi_return
end dynamic

	set From_Dest = @.from_dest
	set Save_Qid = @.save_qid
	# sp27.7 VFGH feature 69723
	set BCI_Service_Instance_ID = call_index()

	test @.msg_name
	case "FGMreqGHN"
		reset Glb_Qry_Grp_Host_Name_Rsp_Rec
		reset L_Error_Flag
		if Glb_Service_Admin_Customer_Index == 0
		then
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.error_indicator = 2
			set L_Error_Flag
			#send_om()
			send_om(
	                        msg_id = counter("30" : "304"),  #SP28.16 RDAF729606
				msg_class = GSL_Internal_Assert_Message_Class,
				poa = GSL_Internal_Assert_Priority,
				title = "REPT INTERNAL ASSERT = 304, SPA=EPPSM",
				message = "Internal System Error - Internal error, Get Glb_Service_Admin_Customer_Index failed",
				message2 =
				"\nCall Instance ID = " : string(call_index()) :
				"\nScenario Location = iscm!message_received"
				)
		end if
		#decode the received message 
		if !L_Error_Flag
		then
			set Glb_Qry_Grp_Host_Name_Req_Dec = spi!decode_query_group_host_name_request_message(spi_protocol_bound, @.payload)
			if Glb_Qry_Grp_Host_Name_Req_Dec.return_code != ire_success
			then
				set Glb_Qry_Grp_Host_Name_Rsp_Rec.error_indicator = 1
				set L_Error_Flag
				#send_om()
				send_om(
	                                msg_id = counter("30" : "201"),  #SP28.16 RDAF729606
					msg_class = GSL_Internal_Assert_Message_Class,
					poa = GSL_Internal_Assert_Priority,
					title = "REPT NETWORK ASSERT=201, SPA=EPPSM",
					message = "Decode Query Group Host Name Request Failed!" :
					"reason=" : string(Glb_Qry_Grp_Host_Name_Req_Dec.return_code),
					message2 =
					"\nCall Instance ID = " : string(call_index()) :
					"\nScenario Location = iscm!message_received"
					)
			end if
			set Glb_Qry_Grp_Host_Name_Req_Rec = Glb_Qry_Grp_Host_Name_Req_Dec.data
		end if
		# check parameters
		if !L_Error_Flag
		then
			if(Glb_Qry_Grp_Host_Name_Req_Rec.secondary_account_id != "")
			then
				set Glb_Qry_Grp_Host_Name_Req_Rec.secondary_account_id = map(Glb_Qry_Grp_Host_Name_Req_Rec.secondary_account_id, "abcdef", "ABCDEF")
				if(Glb_Qry_Grp_Host_Name_Req_Rec.secondary_account_id != "QUYINDEXDB" && length(Glb_Qry_Grp_Host_Name_Req_Rec.secondary_account_id) > 24)
				then
					set Glb_Qry_Grp_Host_Name_Rsp_Rec.error_indicator = 3
					set L_Error_Flag
					#send_om
					send_om(
	                                        msg_id = counter("30" : "201"),  #SP28.16 RDAF729606
						msg_class = GSL_Assert_Message_Class,
						poa = GSL_INAP_Buffer_Assert_Priority,
						title = "REPT NETWORK ASSERT=201, SPA=EPPSM",
						message = "Incoming Message Error - Invalid or missing parameters," :
						" Secondary account ID format error",
						message2 =
						"\nCall Instance ID = " : string(call_index()) :
						"\nScenario Location = iscm!message_received"
						)
				end if
			end if
		end if

		# SP27.9 VFCZ 70577
		# decode operation
		if !L_Error_Flag && Glb_Qry_Grp_Host_Name_Req_Rec.operation.present
		then
			set Query_Group_Operation = Glb_Qry_Grp_Host_Name_Req_Rec.operation.value
		end if

		if(Query_Group_Operation == any("0", "1") &&
			(Glb_Qry_Grp_Host_Name_Req_Rec.secondary_account_id == "" || table_length(Glb_Qry_Grp_Host_Name_Req_Rec.more_account_ids) == 0))
			|| (Query_Group_Operation == any("2", "3") && table_length(Glb_Qry_Grp_Host_Name_Req_Rec.more_account_ids) == 0)
		then
			set Glb_Qry_Grp_Host_Name_Rsp_Rec.error_indicator = 3
			set L_Error_Flag
			#send_om
			send_om(
	                        msg_id = counter("30" : "201"),  #SP28.16 RDAF729606
				msg_class = GSL_Assert_Message_Class,
				poa = GSL_INAP_Buffer_Assert_Priority,
				title = "REPT NETWORK ASSERT=201, SPA=EPPSM",
				message = "Incoming Message Error - Invalid or missing parameters," :
				" mandatory parameter - Secondary_Account_ID or More_Account_IDs missing ",
				message2 = "\nCall Instance ID = " : string(call_index()) :
				"\nScenario Location = iscm!message_received"
				)
		end if
		#end 70577

		if !L_Error_Flag
		then
			if Glb_Qry_Grp_Host_Name_Req_Rec.secondary_account_id == "QUYINDEXDB"
				|| Query_Group_Operation == any("0", "1", "2", "3")# SP27.9 VFCZ 70577
			then
				if Glb_Qry_Grp_Host_Name_Req_Rec.secondary_account_id == "QUYINDEXDB"
				then
					set L_Total_Account_Num = 2
				elif Query_Group_Operation == any("0", "1", "2", "3")
				then
					set L_Total_Account_Num = 0
				end if
				set Glb_More_Account_ID_tbl[] = Glb_Qry_Grp_Host_Name_Req_Rec.more_account_ids[]
				loop Glb_More_Account_ID_tbl
					incr L_Total_Account_Num
					if Glb_More_Account_ID_tbl.value != ""
					then
						set L_Account_ID_List_Rec.Account_ID = Glb_More_Account_ID_tbl.value
						insert L_Account_ID_List_Rec into Account_ID_List_tbl at L_Total_Account_Num
					end if
				end loop Glb_More_Account_ID_tbl
				if Glb_Qry_Grp_Host_Name_Req_Rec.secondary_account_id == "QUYINDEXDB" &&
					Glb_Qry_Grp_Host_Name_Req_Rec.primary_account_id != ""
				then
					set L_Account_ID_List_Rec.Account_ID = Glb_Qry_Grp_Host_Name_Req_Rec.primary_account_id
					insert L_Account_ID_List_Rec into Account_ID_List_tbl at 1
				end if
				if Glb_Qry_Grp_Host_Name_Req_Rec.secondary_account_id == "QUYINDEXDB" &&
					Glb_Qry_Grp_Host_Name_Req_Rec.sponsoring_account_id != ""
				then
					set L_Account_ID_List_Rec.Account_ID = Glb_Qry_Grp_Host_Name_Req_Rec.sponsoring_account_id
					insert L_Account_ID_List_Rec into Account_ID_List_tbl at 2
				end if
			end if
		end if
		if L_Error_Flag
		then
			set Glb_spi_Encoded_rst = spi!encode_query_group_host_name_response_message(spi_protocol_bound, Glb_Qry_Grp_Host_Name_Rsp_Rec)
			iscm!send(routing_type = iscm_one_q_of_qid,
				to_dest = From_Dest,
				save_qid = Save_Qid,
				msg_name = "!FGMrspGHN",
				msg_version = 1,
				payload = Glb_spi_Encoded_rst.data,
				cargo = Glb_InterSPA_cargo_Flag
				)
			return
		end if
		# SP28.11 VFQ F74754
		if Glb_Qry_Grp_Host_Name_Req_Rec.online_hierarchy.present
		then
			set P_S!Request_Hierarchy_Information.Online_Hierarchy =
				Glb_Qry_Grp_Host_Name_Req_Rec.online_hierarchy.value
		end if
		set P_S!Request_Hierarchy_Information.Primary_Account_ID = Glb_Qry_Grp_Host_Name_Req_Rec.primary_account_id
		set P_S!Request_Hierarchy_Information.Secondary_Account_ID = Glb_Qry_Grp_Host_Name_Req_Rec.secondary_account_id
		# V10.5 62977 spa678628cA
		set P_S!Request_Hierarchy_Information.Sponsoring_Account_ID = Glb_Qry_Grp_Host_Name_Req_Rec.sponsoring_account_id
		# V10.13 66403
		set P_S!Request_Hierarchy_Information.Account_ID_List_tbl[] = Account_ID_List_tbl[]
		set P_S!Request_Hierarchy_Information.Total_Account_Number = L_Total_Account_Num
		set P_S!Request_Hierarchy_Information.Call_Index = call_index()
		# SP27.9 VFCZ 70577
		set P_S!Request_Hierarchy_Information.Operation = Query_Group_Operation

		next event P_S!Request_Hierarchy_Information
		return
		# SP27.7 Feauture 69716 VFGH
	case any("GPRSSIMRtr", "CLI_All", "CLI_Attach", "CLI_Detach",
		# sp27.7 VFGH feature 69723
			"CS_CLIINFO_Rtr", "CS_CLIINFO_Del", "CS_CLIINFO_Rpl",
			"CLIINFO_Rpl", "CLIINFO_Ins")

		# Inter-SPA request from ECTRL
		set Request_Info_From_ECTRL.Msg_N = @.msg_name
		set Request_Info_From_ECTRL.Payload = @.payload
		next event Request_Info_From_ECTRL
		return

	end test

	next event Service_Terminate_Call
	return

end event iscm!message_received

#---------------------------------------------
#R27.7 Inter-spa commu & 3D tool test code
#---------------------------------------------
event iscm!message_sent

	next event Service_Terminate_Call
	return

end event iscm!message_sent

#---------------------------------------------
#R27.7 Inter-spa commu & 3D tool test code
#---------------------------------------------
event iscm!message_send_failed
%% if {$DEBUG =="ON"} {
	if Glb_DEBUG_LEVEL > 3
        then
                print("iscm!message_send_failed")
        end if
%% }
        #SP28.16 RDAF729606
        Parse_Object(",", string(Glb_Internal_Operation_Assert_Title))
        if Glb_Parse_Temp_Count > 0
        then
        	set Glb_Temp_String_Parsed = map(Glb_Parsed,
        		"abcdefghijklmnopqrstuvwxzyABCDEFGHIJKLMNOPQRSTUVWXYZ= ", "")
        else
        	set Glb_Temp_String_Parsed = "000"
        end if
			
	send_om(
	        msg_id = counter("30" : Glb_Temp_String_Parsed),
		msg_class = GSL_Internal_Assert_Message_Class,
		title = Glb_Internal_Operation_Assert_Title,
		poa = GSL_Internal_Assert_Priority,
		message = "message send fail - " : @.msg_name,
		message2 = "\nCall Instance ID = " : string(call_index()) :
		"\nScenario Location = iscm!message_send_failed"
		)

	next event Service_Terminate_Call
	return

end event iscm!message_send_failed

# SP27.7 Feature 69716 VFGH
event Send_Info_Back_To_ECTRL

	# SP28.8 72933
	if Use_LDAP_For_Inter_SPA_Flag
	then
		next event Send_InterSpa_Request_By_LDAP
		return
	else
		next event Send_To_InterSpa_Request
		return
	end if

end event Send_Info_Back_To_ECTRL

# SP28.8 72933
#--------------------------------------------------------------------------------
# Event: 	Send_InterSpa_Request_By_LDAP
#
# Description:	This event sends Inter-SPA result message to protocol layer. 
#		This event is used to instead of event Send_To_InterSpa_Request
#		when using LDAP for Inter-SPA request.
#
#--------------------------------------------------------------------------------
event Send_InterSpa_Request_By_LDAP
dynamic
	L_Encoded_Message			itu_tcap_enc_bi_return
end dynamic

	if InterSPA_Decode_Fail
	then
		# Payload decode error, send back to ECTRL with result_code 01
		set S_P!Request_Inter_SPA_Result.result_code = "01"
		send(to = Inter_eCS_COMM_FSM_Call_Index,
			event = S_P!Request_Inter_SPA_Result,
			ack = false)

		next event Service_Terminate_Call
		return
	end if

	# Encode Inter-SPA message
	set L_Encoded_Message = spi!encode_ectrl_eppsm_record(
		spi_protocol_bound, Message_For_Ectrl_EPPSM_Rec)
	if L_Encoded_Message.return_code == ire_success
	then
		# Succeed, send back to ECTRL with result_code 00
		set S_P!Request_Inter_SPA_Result.result_code = "00"
		set S_P!Request_Inter_SPA_Result.return_data = L_Encoded_Message.data
		send(to = Inter_eCS_COMM_FSM_Call_Index,
			event = S_P!Request_Inter_SPA_Result,
			ack = false)

		next event Service_Terminate_Call
		return
	else
		# Encode Inter-SPA message failed
                #SP28.16 RDAF729606
                Parse_Object(",", string(Glb_Internal_Operation_Assert_Title))
                if Glb_Parse_Temp_Count > 0
                then
                	set Glb_Temp_String_Parsed = map(Glb_Parsed,
                		"abcdefghijklmnopqrstuvwxzyABCDEFGHIJKLMNOPQRSTUVWXYZ= ", "")
                else
                	set Glb_Temp_String_Parsed = "000"
                end if
			
		send_om(
	                msg_id = counter("30" : Glb_Temp_String_Parsed),
			msg_class = GSL_Internal_Assert_Message_Class,
			title = Glb_Internal_Operation_Assert_Title,
			poa = GSL_Internal_Assert_Priority,
			message = "Internal System Error - Encode Message Failed: " :
			string(L_Encoded_Message.return_code),
			message2 = "\nCall Instance ID = " : string(call_index()) :
			"\nScenario Location = Send_InterSpa_Request_By_LDAP"
			)

		# Encode error, send back to ECTRL with result_code 99
		set S_P!Request_Inter_SPA_Result.result_code = "99"
		send(to = Inter_eCS_COMM_FSM_Call_Index,
			event = S_P!Request_Inter_SPA_Result,
			ack = false)

		next event Service_Terminate_Call
		return
	end if

end event Send_InterSpa_Request_By_LDAP

#------------------------------------------------------------------------------	
# Event:	Get_Access_Index
#
# Description:	The event generate the access index to the SERVICE_ADMIN_Access_String
#------------------------------------------------------------------------------	
event Get_Access_Index
	set Glb_Service_Admin_Customer_Index =
		routing_string!lookup(SERVICE_ADMIN_Access_String)
	if Glb_Service_Admin_Customer_Index == 0
	then
		schedule(clock = clock() + 3,
			event = Get_Access_Index)
	else

		print("Glb_Service_Admin_Customer_Index= ",
			Glb_Service_Admin_Customer_Index)
	end if

	next event Service_Terminate_Call
end event Get_Access_Index
#------------------------------------------------------------------------------	
# Event:	RTDB_AttachFailed
#
# Description:	After attach failed, will end call.
#------------------------------------------------------------------------------	
event RTDB_AttachFailed
	send_om(
	        msg_id = counter("30" : "305"),  #SP28.16 RDAF729606
		msg_class = GSL_Internal_Assert_Message_Class,
		poa = GSL_Internal_Assert_Priority,
		title = "REPT INTERNAL ASSERT=305, SPA=EPPSM",
		message = "Intenal System Error - RTDB operation failed, RTDB Name = " : @.RTDB_Name : ".",
		message2 =
		"\nSubscriber ID = " :
		"\nCall Instance ID = " : string(call_index()) :
		"\nScenario Location = RTDB_AttachFailed" :
		"\nRTDB Name=" : @.RTDB_Name :
		"\nFailure Reason=" : string(@.Reason)
		)
	next state Account_Manager
	next event Service_Terminate_Call
end event RTDB_AttachFailed
#---------------------------------------------------------------------
# Event:        Service_Terminate_Call
#
# Description:  The event call end_call, and terminate the call instance.
#
#---------------------------------------------------------------------
event Service_Terminate_Call
	end_call
end event Service_Terminate_Call
#---------------------------------------------------------------------
# Event : 	Request_Query_Index_DB
#
# Description:  Query index DB GPRSSIM to get Account host name
#
#----------------------------------------------------------------------
event Request_Query_Index_DB

	while Account_ID_Pos <= Total_Account_Number
	do
		if element_exists(Account_ID_List_tbl, Account_ID_Pos)
		then
			set Account_ID_List_tbl.index = Account_ID_Pos
			set Retrieve_GPRSSIM_For = RGR_Normal_Account
			set GPRSSIM_Retrieve.Key_Index = Account_ID_List_tbl.Account_ID
			next event GPRSSIM_Retrieve
			return
		else
			if Account_ID_Pos > 2
			then
				set Account_SCP_List = Account_SCP_List : ","
			end if
			incr Account_ID_Pos
		end if
	end while

	# remove the last ","
	set Account_SCP_List = substring(Account_SCP_List, 1, length(Account_SCP_List) - 1)
	next event Determine_Hierarchy_Complete_1
	return

end event Request_Query_Index_DB
#---------------------------------------------------------------------
# Event :     Request_Query_Group_Info
#
# Description: this event is to query Group Info.
#             If the operation is 0 or 1, the service need query intra-group information,
#             if the operation is 0 or 2, the service need query SCP host name.
#	      (SP27.9 VFCZ 70577)
#----------------------------------------------------------------------
event Request_Query_Group_Info
dynamic
	Local_Group_ID				string
	Local_Tbl_Key				string
	Local_Result				match_data
end dynamic
	# SP28.14 75195
	if cDB_RTDB_Enabled
	then
		next event Req_Query_Group_Info_From_CDB_RTDB
		return
	end if

	while Account_ID_Pos <= Total_Account_Number
	do
		if element_exists(Account_ID_List_tbl, Account_ID_Pos)
		then
			set Account_ID_List_tbl.index = Account_ID_Pos
			set Local_Group_ID = Account_ID_List_tbl.Account_ID
			if Query_Group_Operation == any("0", "1")
			then
				set Local_Tbl_Key = Secondary_Account_ID : ":" : Local_Group_ID
				set Local_Result = best_match(Centralized_Group_tbl, Local_Tbl_Key)
				test Local_Result.match_type
				case e_prefix_match
					set Intra_Group_Indicator = Intra_Group_Indicator : "1" : ","
				other
					set Intra_Group_Indicator = Intra_Group_Indicator : "0" : ","
				end test
			end if
			if Query_Group_Operation == any("0", "2")
			then
				set Retrieve_GPRSSIM_For = RGR_Intra_Group
				set GPRSSIM_Retrieve.Key_Index = Account_ID_List_tbl.Account_ID
				next event GPRSSIM_Retrieve
				return
			end if
			incr Account_ID_Pos
		else
			set Account_SCP_List = Account_SCP_List : ","
			set Intra_Group_Indicator = Intra_Group_Indicator : ","
			incr Account_ID_Pos
		end if
	end while

	if Query_Group_Operation == any("0", "1")
	then
		incr Glb_Service_Measurement_Rec.Number_of_Successful_cDB_Accesses
	end if
	# remove the last ","
	set Account_SCP_List = substring(Account_SCP_List, 1, length(Account_SCP_List) - 1)
	set Intra_Group_Indicator = substring(Intra_Group_Indicator, 1, length(Intra_Group_Indicator) - 1)

	reset Intra_Hierarchy_Flag

	next event Determine_Hierarchy_Complete_1
	return

end event Request_Query_Group_Info

#---------------------------------------------------------------------
# Event :       Upd_Counter_Bro_Para
#
# Description: 	This event is added for 72139 that Transfer update counter
#		or broadcast parameter ot group or Line MAS
#--------------------------------------------------------------------
event Upd_Counter_Bro_Para

	set Check_LDAP_Link_Return_Point = GCF_Upd_Counter_Broadcast_Para
	set Request_Inter_HOST_LDAP_Link_Check.Remote_SCP_Name = Member_SCP_Name
	next event Request_Inter_HOST_LDAP_Link_Check
	return

end event Upd_Counter_Bro_Para

event Upd_Counter_Bro_Para_Continue
dynamic
	#SP28.13 VzW 75145
        Local_LDAP_Timer	counter
	L_Use_Data_Req_Timer	flag
	L_EPM_Key		EPM_Key_Type
end dynamic

	set Glb_Inter_HOST_LDAP_Link_tbl.index = Member_SCP_Name
	if find("BROADCAST_SESSION_PARA", LDAP_Temp_String) != 0
	then
		Parse_Object("#", LDAP_Temp_String)
		set Glb_Temp_String1 = Glb_Parsed
		Parse_Object("=", Glb_Remainder)
		if Glb_Parsed == "HOST"
		then
			Parse_Object(":", Glb_Remainder)
			set LDAP_Temp_String = Glb_Temp_String1 : "#HOST=" : Member_SCP_Name :
				":" : Glb_Remainder
		else
			set LDAP_Temp_String = Glb_Temp_String1 : "#HOST=" : Member_SCP_Name :
				":" : Glb_Parsed : "=" : Glb_Remainder
		end if
	end if 
	incr Data_Req_Snt_Msg_Num
	set Data_Req_To_Des_Flag
	test Member_Group_ID_Type
	case "S"
		incr Data_Req_Snt_Msg_Num_Broadcast
	case "G"
		incr Data_Req_Snt_Msg_Num_U_Or_Q
	end test
	#SP28.13 VzW 75145
	set L_EPM_Key.Key_String_1 = "SEPERATE_TIMER:ALL:ALL:ALL"
	set L_EPM_Key.Key_String_2 = "ALL:ALL"
	set L_EPM_Key.Mapping_Parameter_6 = "ALL"
	set L_EPM_Key.Mapping_Parameter_7 = "ALL"
	set L_EPM_Key.Mapping_Parameter_8 = "ALL"
	if element_exists(Enhanced_Parameter_Mapping_tbl, L_EPM_Key)
	then
       		set Enhanced_Parameter_Mapping_tbl.index = L_EPM_Key
	       	if Enhanced_Parameter_Mapping_tbl.Output_Value == "TRUE"
       		then
	             set L_Use_Data_Req_Timer
	        end if
	end if
	if L_Use_Data_Req_Timer 
	then
		set Local_LDAP_Timer = Data_Request_LDAP_Timer
		if Timer_In_1Percent_Second
                then
                        set Glb_LDAP_Return = ldap!set_timer_granularity(timer_granularity_10_millisecond)
                        if Local_LDAP_Timer == 0
                        then
                                set Local_LDAP_Timer = 400
                        end if 
                elif Local_LDAP_Timer == 0
                then
                        set Local_LDAP_Timer = 40
                end if
	else
		set Local_LDAP_Timer = 40
	end if

	data_request!read(instance = Glb_Inter_HOST_LDAP_Link_tbl.Link_Instance,
		subscriber_id_etc = LDAP_Temp_String,
		tenths_timeout = Local_LDAP_Timer)
	return

end event Upd_Counter_Bro_Para_Continue

event Upd_Counter_Bro_Para_Result

	test @.Result_Code
	case GRC_Success
		set Send_Upd_Counter_Bro_Para_Res.Result_Code = "00"
		next event Send_Upd_Counter_Bro_Para_Res
		return
	case GRC_Query_With_Healing
		if Glb_IDX_QRY_FSM_Customer_Index == 0
		then
			set Send_Upd_Counter_Bro_Para_Res.Result_Code = "99"
			next event Send_Upd_Counter_Bro_Para_Res
			return
		end if
		set Request_Self_Learning_Healing.Customer_Call_ID = call_index()
		set Request_Self_Learning_Healing.ID = Member_Group_ID
		set Request_Self_Learning_Healing.ID_Type = Member_Group_ID_Type
	        set Request_Self_Learning_Healing.Learning_Healing_Type = Self_Healing #72850
                set Req_SA_To_IQRY_Sending_Flag
		send(to = Glb_IDX_QRY_FSM_Customer_Index,
			event = Request_Self_Learning_Healing,
			ack = true)
		return
	case GRC_Failed
		set Send_Upd_Counter_Bro_Para_Res.Result_Code = "99"
		next event Send_Upd_Counter_Bro_Para_Res
		return
	case GRC_Duplicated_Message
		set Send_Upd_Counter_Bro_Para_Res.Result_Code = "07"
		next event Send_Upd_Counter_Bro_Para_Res
		return
	case GRC_Not_Find #_add_in_73582
		set Send_Upd_Counter_Bro_Para_Res.Result_Code = "02"
		next event Send_Upd_Counter_Bro_Para_Res
		return
	case GRC_Busy #SP28.10 feature 73939
		set Send_Upd_Counter_Bro_Para_Res.Result_Code = "51"
                next event Send_Upd_Counter_Bro_Para_Res
                return
	other
		#This result is impossible and do nothing
	end test

end event Upd_Counter_Bro_Para_Result

#---------------------------------------------------------------------
# Event :       Request_Generate_Service_Measurement
#
# Description: This event is used to request generating service measurement
#
#------------------------------------------------------------------
event Request_Query_Hier_Info
dynamic

	Local_Group_ID				string
	Local_Branch_ID				string
	Local_Account_Number			counter
	Local_Search_Level			counter
	Local_Top_Has_Found			flag
	Local_Branch_ID_Invalid			flag
	Local_BR_Has_Found			flag
	Local_Relation_Has_Found		flag
	Local_BR_Level				counter	#SP28.9 73335
end dynamic
	#SP28.10 72817
	if !Query_Sponsoring_Host_Done && Sponsoring_Account_ID != ""
	then
		set Query_Sponsoring_Host_Done
		set Retrieve_GPRSSIM_For = RGR_Query_Operation
		set GPRSSIM_Retrieve.Key_Index = Sponsoring_Account_ID
		next event GPRSSIM_Retrieve
		return
	end if
	
	# SP28.14 75195
	if cDB_RTDB_Enabled
	then
		reset Group_ID_List_tbl[]
		if Secondary_Account_ID != "" && Query_Group_Operation != "2"
		then
			reset Secondary_Acc_tbl[]
			set Retrieve_CD_RTDB_Step = Req_Qry_Sec_Acc_Hier_Info
			set CDB_RTDB_Max_Records = 100
			reset RTDB_Exact_Match
			reset Group_ID_Pos
			set Request_CDB_RTDB_Retrieve.key_index = Secondary_Account_ID : ":"
			next event Request_CDB_RTDB_Retrieve
			return
		end if
		reset Hierarchy_Structure_tbl[]
		set Account_Number = 1
		next event Req_Qry_Account_Hier_Info
		return
	end if

	if Secondary_Account_ID != "" && Query_Group_Operation != "2"
	then					
		reset Glb_Secondary_Acc_tbl[]
		set Glb_Temp_String2 = Secondary_Account_ID : ":"
		set Glb_Temp_String2 = index_next(Centralized_Group_tbl, Glb_Temp_String2)
		Parse_Object(":", Glb_Temp_String2)

		while Glb_Parsed == Secondary_Account_ID && Glb_Remainder != ""
		do
			set Local_Branch_ID = Glb_Remainder
			reset Local_Top_Has_Found
			while !Local_Top_Has_Found
			do
				set Local_Group_ID = Glb_Remainder
				if !element_exists(Glb_Secondary_Acc_tbl, Local_Group_ID)
				then
					insert into Glb_Secondary_Acc_tbl at Local_Group_ID
				else
					set Local_Top_Has_Found
					exit while
				end if 

				set Centralized_Group_tbl.index = Glb_Parsed : ":" : Local_Group_ID
				if Centralized_Group_tbl.Top_Account_Indicator
				then
					set Local_Top_Has_Found
					exit while
				end if 

				set Glb_Temp_String2 = Local_Group_ID : ":"
				set Glb_Temp_String2 = index_next(Centralized_Group_tbl, Glb_Temp_String2)
				Parse_Object(":", Glb_Temp_String2)

				if Glb_Parsed != Local_Group_ID || Glb_Remainder == ""
				then
					set Local_Top_Has_Found
					exit while
				end if
			end while

			set Glb_Temp_String2 = Secondary_Account_ID : ":" : Local_Branch_ID
			set Glb_Temp_String2 = index_next(Centralized_Group_tbl, Glb_Temp_String2)
			Parse_Object(":", Glb_Temp_String2)
		end while 

	end if

	reset Hierarchy_Structure_tbl[]
	set Local_Account_Number = 1

	while Local_Account_Number <= Total_Account_Number && Total_Account_Number > 0
	do
		set Local_Search_Level = 0
		reset Local_Top_Has_Found
		reset Local_BR_Has_Found
		reset Local_Relation_Has_Found
		reset Local_Branch_ID_Invalid

		insert into Hierarchy_Structure_tbl at Local_Account_Number

		set Account_ID_List_tbl.index = Local_Account_Number
		set Local_Group_ID = Account_ID_List_tbl.Account_ID
		set Glb_Temp_String2 = Primary_Account_ID : ":" : Local_Group_ID
		set Glb_Best_Match = best_match(Centralized_Group_tbl, Glb_Temp_String2)
		if Glb_Best_Match.match_type != e_prefix_match || Local_Group_ID == ""
		then
			set Local_Branch_ID_Invalid
		end if
		if !Local_Branch_ID_Invalid
		then    
			set Hierarchy_Structure_tbl.present
			Parse_Object(":", Glb_Best_Match.match_value)
			reset Glb_Branch_Acc_List_tbl[]
			while !Local_Top_Has_Found
			do
				incr Local_Search_Level
				insert into Glb_Branch_Acc_List_tbl at Local_Search_Level
				set Glb_Branch_Acc_List_tbl.Account_ID = Local_Group_ID
				set Centralized_Group_tbl.index = Glb_Parsed : ":" : Glb_Remainder
				if !Local_BR_Has_Found && Centralized_Group_tbl.Billing_Responsibility_Indicator
				then
					set Local_BR_Has_Found
					set Hierarchy_Structure_tbl.BR_Level = Local_Search_Level
				end if
				if !Local_Relation_Has_Found && Query_Group_Operation != "2"
					&& Secondary_Account_ID != ""
				then
					if element_exists(Glb_Secondary_Acc_tbl, Local_Group_ID)
					then
						set Local_Relation_Has_Found
						set Hierarchy_Structure_tbl.Relation_Level = Local_Search_Level
					end if 
				end if

				if Centralized_Group_tbl.Top_Account_Indicator
				then
					set Local_Top_Has_Found
					set Hierarchy_Structure_tbl.Level_Number = Local_Search_Level
					if Query_Group_Operation != "1"
					then
						set Hierarchy_Structure_tbl.SCP_Name = Local_Group_ID
					end if
					exit while
				end if

				set Glb_Temp_String1 = Local_Group_ID

				set Glb_Temp_String2 = Local_Group_ID : ":"
				set Glb_Temp_String2 = index_next(Centralized_Group_tbl, Glb_Temp_String2)
				Parse_Object(":", Glb_Temp_String2)

				if Glb_Temp_String1 == Glb_Parsed && Glb_Remainder != ""
				then
					set Local_Group_ID = Glb_Remainder
				else
					set Local_Top_Has_Found
					set Hierarchy_Structure_tbl.Level_Number = Local_Search_Level
					if Query_Group_Operation != "1"
					then
						set Hierarchy_Structure_tbl.SCP_Name = Local_Group_ID
					end if
					exit while
				end if
			end while
			set Hierarchy_Structure_tbl.Account_List_rec.Account_List_tbl[] = Glb_Branch_Acc_List_tbl[]
		end if
		incr Local_Account_Number
	end while


	next event Req_Message_For_Ectrl_EPPSM
	return
end event Request_Query_Hier_Info

event Request_Query_Hier_Info_Continue
	while 0 < Account_ID_Pos && Account_ID_Pos <= Total_Account_Number
	do	
		set Hierarchy_Structure_tbl.index = Account_ID_Pos
		if Hierarchy_Structure_tbl.SCP_Name == ""
		then
			incr Account_ID_Pos
		else
			set Retrieve_GPRSSIM_For = RGR_Intra_Group
			set GPRSSIM_Retrieve.Key_Index = Hierarchy_Structure_tbl.SCP_Name
			next event GPRSSIM_Retrieve
			return
		end if 
	end while

	next event Determine_Hierarchy_Complete_1
	return

end event Request_Query_Hier_Info_Continue

event Req_Sec_Account_Hier_To_Top

	while Group_ID_Pos < Total_Group_IDs_Length
	do 
		incr Group_ID_Pos
		set Group_ID_List_tbl.index = Group_ID_Pos
		set CDB_RTDB_Max_Records = 1
		reset RTDB_Exact_Match
		set Retrieve_CD_RTDB_Step = Req_Qry_Sec_Acc_Hier_Info_To_Top
		set Request_CDB_RTDB_Retrieve.key_index = Group_ID_List_tbl.Group_ID : ":"
		next event Request_CDB_RTDB_Retrieve
		return
	end while
	reset Hierarchy_Structure_tbl[]
	set Account_Number = 1
	next event Req_Qry_Account_Hier_Info
	return
end event Req_Sec_Account_Hier_To_Top

event Req_Qry_Account_Hier_Info
	
	while Account_Number <= Total_Account_Number && Total_Account_Number > 0
	do	
		set Search_Level = 0
		reset Top_Has_Found
		reset BR_Has_Found
		reset Relation_Has_Found

		insert into Hierarchy_Structure_tbl at Account_Number
		set Account_ID_List_tbl.index = Account_Number
		if Account_ID_List_tbl.Account_ID == ""
		then
			incr Account_Number
		else
			reset Branch_Acc_List_tbl[]
			set Retrieve_CD_RTDB_Step = Req_Primary_Group_Exist
			set Request_CDB_RTDB_Retrieve.key_index = Primary_Account_ID :":": Account_ID_List_tbl.Account_ID
			set CDB_RTDB_Max_Records = 1
			set RTDB_Exact_Match
			next event Request_CDB_RTDB_Retrieve
			return
		end if
	end while

	next event Req_Message_For_Ectrl_EPPSM
	return	

end event Req_Qry_Account_Hier_Info

event Req_Message_For_Ectrl_EPPSM
dynamic
	Local_Group_ID				string
	Local_Account_Number			counter
	Local_BR_Level				counter
end dynamic
	#SP28.9 73335 after get hierarchy info, we continue the base logic
	if Message_For_Ectrl_EPPSM_Rec.check_br.value
	then
	
		#Check BR at here
		reset Message_For_Ectrl_EPPSM_Rec.check_br_result
		set Message_For_Ectrl_EPPSM_Rec.check_br_result.present
		set Local_Account_Number = 1
		while Local_Account_Number <= Total_Account_Number
		do 
			set Hierarchy_Structure_tbl.index = Local_Account_Number
			set Local_BR_Level = Hierarchy_Structure_tbl.BR_Level
			set Local_Group_ID = Hierarchy_Structure_tbl.Account_List_rec.Account_List_tbl[Local_BR_Level].Account_ID
			if(Local_Group_ID == Message_For_Ectrl_EPPSM_Rec.account_id)
			then
				#set Message_For_Ectrl_EPPSM_Rec.check_br_result.present
				set Message_For_Ectrl_EPPSM_Rec.check_br_result.value
				exit while
			end if
			incr Local_Account_Number
		end while
		#Continue the base logic
		set Retrieve_GPRSSIM_For = RGR_External_Query
		set GPRSSIM_Retrieve.Key_Index = Message_For_Ectrl_EPPSM_Rec.account_id
		next event GPRSSIM_Retrieve
		return
	end if
	#SP28.9 73335

	if Query_Group_Operation == any("0", "1", "2")
	then
		incr Glb_Service_Measurement_Rec.Number_of_Successful_cDB_Accesses
	end if

	if Query_Group_Operation == any("0", "2")
	then
		set Account_ID_Pos = 1
		next event Request_Query_Hier_Info_Continue
		return
	end if

	next event Determine_Hierarchy_Complete_1

	return

end event Req_Message_For_Ectrl_EPPSM

event Req_Query_Group_Info_From_CDB_RTDB

	while Account_ID_Pos <= Total_Account_Number
	do
		if element_exists(Account_ID_List_tbl, Account_ID_Pos)
		then
			set Account_ID_List_tbl.index = Account_ID_Pos
			if Query_Group_Operation == any("0", "1")
			then
				set Retrieve_CD_RTDB_Step = Req_Group_Info
				set CDB_RTDB_Max_Records = 1
				set RTDB_Exact_Match
				set Request_CDB_RTDB_Retrieve.key_index = Secondary_Account_ID : ":" : Account_ID_List_tbl.Account_ID
				next event Request_CDB_RTDB_Retrieve
				return
			end if
			if Query_Group_Operation == any("0", "2")
			then
				set Retrieve_GPRSSIM_For = RGR_Intra_Group
				set GPRSSIM_Retrieve.Key_Index = Account_ID_List_tbl.Account_ID
				next event GPRSSIM_Retrieve
				return
			end if
			incr Account_ID_Pos
		else
			set Account_SCP_List = Account_SCP_List : ","
			set Intra_Group_Indicator = Intra_Group_Indicator : ","
			incr Account_ID_Pos
		end if
	end while
	
	if Query_Group_Operation == any("0", "1")
	then
		incr Glb_Service_Measurement_Rec.Number_of_Successful_cDB_Accesses
	end if
	# remove the last ","
	set Account_SCP_List = substring(Account_SCP_List, 1, length(Account_SCP_List) - 1)
	set Intra_Group_Indicator = substring(Intra_Group_Indicator, 1, length(Intra_Group_Indicator) - 1)
	reset Intra_Hierarchy_Flag
	next event Determine_Hierarchy_Complete_1
	return
	
end event Req_Query_Group_Info_From_CDB_RTDB

event P_S_Req_Group_Info_To_Top

	while Group_ID_Pos < Total_Group_IDs_Length
	do 
		reset Top_Has_Found
		reset BR_Has_Found
		incr Group_ID_Pos
		set Group_ID_List_tbl.index = Group_ID_Pos
		incr Branch_Number
		set Group_ID = Group_ID : "H" : string(Branch_Number) : "=" : Group_ID_List_tbl.Group_ID : ":"
		if Group_ID_List_tbl.BR_flag
		then
			set BR_Has_Found
			set BR_String = ",BR=" : Group_ID_List_tbl.Group_ID
		end if
		set CDB_RTDB_Max_Records = 1
		reset RTDB_Exact_Match
		set Retrieve_CD_RTDB_Step = P_S_Req_Group_Info_Online_To_Top
		set Request_CDB_RTDB_Retrieve.key_index = Group_ID_List_tbl.Group_ID  : ":"
		next event Request_CDB_RTDB_Retrieve
		return
	end while
	# remove the last "," 
	if Group_IDs != ""
	then
		set Group_IDs = substring(Group_IDs, 1, length(Group_IDs) - 1)
	end if
	set S_P!Request_Group_Information_Result.Account_List = Group_IDs
	send(to = Inter_eCS_COMM_FSM_Call_Index,
		event = S_P!Request_Group_Information_Result,
		ack = false)
	next event Service_Terminate_Call
	return
end event P_S_Req_Group_Info_To_Top

#---------------------------------------------------------------------
# SP28.7, Feature 72483
#
# Event :       event Req_Qry_Hier_Info_For_Top_Acct
#
# Description: This event is used to Get hierarchy brach for given
#		BR Account ID.
#
#------------------------------------------------------------------
event Req_Qry_Hier_Info_For_Top_Acct
dynamic
	Local_Group_ID				string
	Local_Search_Level			counter
end dynamic
	reset Hierarchy_Structure_tbl[]
	reset Glb_Branch_Acc_List_tbl[]

	insert into Hierarchy_Structure_tbl at 1
	set Account_ID_List_tbl.index = 1
	set Local_Group_ID = Account_ID_List_tbl.Account_ID

	set Hierarchy_Structure_tbl.present
	
	# SP28.14 75195
	if cDB_RTDB_Enabled
	then	
		reset Top_Has_Found
		set Search_Level = 1
		insert into Branch_Acc_List_tbl at Search_Level
		set Branch_Acc_List_tbl.Account_ID = Account_ID_List_tbl.Account_ID
		set Retrieve_CD_RTDB_Step = Req_Qry_Hier_Info_For_Acct
		set Request_CDB_RTDB_Retrieve.key_index = Account_ID_List_tbl.Account_ID : ":"
		set CDB_RTDB_Max_Records = 1
		reset RTDB_Exact_Match
		next event Request_CDB_RTDB_Retrieve
		return
	end if

	while(true)
	do
		incr Local_Search_Level
		insert into Glb_Branch_Acc_List_tbl at Local_Search_Level
		set Glb_Branch_Acc_List_tbl.Account_ID = Local_Group_ID
		set Glb_Temp_String1 = Local_Group_ID
		set Glb_Temp_String2 = Local_Group_ID : ":"
		set Glb_Temp_String2 = index_next(Centralized_Group_tbl, Glb_Temp_String2)
		Parse_Object(":", Glb_Temp_String2)
		if Glb_Temp_String1 == Glb_Parsed && Glb_Remainder != ""
			&& !Centralized_Group_tbl[Glb_Temp_String2].Top_Account_Indicator #ih_cr32351
		then
			set Local_Group_ID = Glb_Remainder
		else
			#ih_cr32351
			if Glb_Remainder != "" && Glb_Temp_String1 == Glb_Parsed
			then
				incr Local_Search_Level
				insert into Glb_Branch_Acc_List_tbl at Local_Search_Level
				set Glb_Branch_Acc_List_tbl.Account_ID = Glb_Remainder
			end if
			set Hierarchy_Structure_tbl.Level_Number = Local_Search_Level
			exit while
		end if
	end while
	set Hierarchy_Structure_tbl.Account_List_rec.Account_List_tbl[] =
		Glb_Branch_Acc_List_tbl[]
	incr Glb_Service_Measurement_Rec.Number_of_Successful_cDB_Accesses
	if Sponsoring_Account_ID != ""
	then
		set Retrieve_GPRSSIM_For = RGR_Sponsoring_Account
		set GPRSSIM_Retrieve.Key_Index = Sponsoring_Account_ID
		next event GPRSSIM_Retrieve
		return
	else
		next event Determine_Hierarchy_Complete_1
		return
	end if
end event Req_Qry_Hier_Info_For_Top_Acct

#---------------------------------------------------------------------
# Event :       Request_Generate_Service_Measurement
#
# Description: This event is used to request generating service measurement
#
#------------------------------------------------------------------
event Request_Generate_Service_Measurement
dynamic
	Local_Server_XP_Dest			xp_dest
end dynamic
	reset Service_Measurement_Handling
	set Service_Measurement_Handling.Content = Glb_Service_Measurement_Rec
	set Local_Server_XP_Dest = routing_string!xp_server_lookup("Svr_Adm_Access_Key")
	if Local_Server_XP_Dest != xp_dest("")
	then
		reset Glb_Service_Measurement_Rec
		xp_send(to = Local_Server_XP_Dest,
			event = Service_Measurement_Handling,
			ack = false)
	end if
	# schedule the next event
	schedule(clock = clock() + Glb_Service_Measurement_Interval,
		to = customer_index(),
		event = Request_Generate_Service_Measurement)
	end_call
	return

end event Request_Generate_Service_Measurement
#--------------------------------------------------------------------------
# Event:        Attach_Inter_HOST_Dataview
#
# Description:
#       This event attach the data request dataview for Inter SCP LDAP request
#--------------------------------------------------------------------------
event Attach_Inter_HOST_Dataview
dynamic
	Local_Clock				counter
end dynamic
	# in case the link table is interrupt by other call, set the index again.
	set Glb_Inter_HOST_LDAP_Link_tbl.index = Member_SCP_Name
	#SP28.5 72113
	set Local_Clock = clock()
	if Glb_Inter_HOST_LDAP_Link_tbl.Retried_Times >= LDAP_Link_Retry_Limit + 1 &&
		LDAP_Link_Failover_Period > 0 &&
		Local_Clock > (LDAP_Link_Failover_Period * 60 + Glb_Inter_HOST_LDAP_Link_tbl.Last_Attach_Time)
	then
		reset Glb_Inter_HOST_LDAP_Link_tbl.Retried_Times
	end if

	set Glb_Inter_HOST_LDAP_Link_tbl.Attach_Inprog
	set Inter_Host_DR_Dataview_Name = Glb_Inter_HOST_LDAP_Link_tbl.index : "_request_data"
	data_request!attach_user(
		dataview_name = Inter_Host_DR_Dataview_Name,
		tenths_timeout = 40
		)
	return
end event Attach_Inter_HOST_Dataview

#---------------------------------------------------------------------
# Event:	Request_Inter_HOST_LDAP_Link_Check
#
# Description:	This event is used to check whether the link is available,
#		if unavailable, then attach the link
#
#---------------------------------------------------------------------
event Request_Inter_HOST_LDAP_Link_Check

	if !element_exists(Glb_Inter_HOST_LDAP_Link_tbl, @.Remote_SCP_Name)
	then
		insert into Glb_Inter_HOST_LDAP_Link_tbl at @.Remote_SCP_Name
		set Inter_Host_DR_Dataview_Name = @.Remote_SCP_Name : "_request_data"
		set Glb_Inter_HOST_LDAP_Link_tbl.Attach_Inprog
		set Glb_Inter_HOST_LDAP_Link_tbl.Last_Attach_Time = clock()
		data_request!attach_user(
			dataview_name = Inter_Host_DR_Dataview_Name,
			tenths_timeout = 40)
		return
	else
		set Glb_Inter_HOST_LDAP_Link_tbl.index = @.Remote_SCP_Name
		if Glb_Inter_HOST_LDAP_Link_tbl.Link_Status == DR_Available
		then
			set Request_Inter_HOST_LDAP_Link_Check_Result.Available
			next event Request_Inter_HOST_LDAP_Link_Check_Result
			return
		else
			if !Glb_Inter_HOST_LDAP_Link_tbl.Attach_Inprog &&
				(Glb_Inter_HOST_LDAP_Link_tbl.Retried_Times < LDAP_Link_Retry_Limit + 1 ||
				(Glb_Inter_HOST_LDAP_Link_tbl.Retried_Times >= LDAP_Link_Retry_Limit + 1 &&
				LDAP_Link_Failover_Period > 0 &&
				clock() > (LDAP_Link_Failover_Period * 60 + Glb_Inter_HOST_LDAP_Link_tbl.Last_Attach_Time))
				)
			then
				set Inter_Host_DR_Dataview_Name
					= Glb_Inter_HOST_LDAP_Link_tbl.index : "_request_data"
				data_request!detach_user(
					instance = Glb_Inter_HOST_LDAP_Link_tbl.Link_Instance,
					tenths_timeout = 40)
				return
			else
				next event Request_Inter_HOST_LDAP_Link_Check_Result
				return
			end if
		end if
	end if
end event Request_Inter_HOST_LDAP_Link_Check

event data_request!attach_user_completed

	# in case the link table is interrupt by other call, set the index again.
	set Glb_Inter_HOST_LDAP_Link_tbl.index = Member_SCP_Name
	reset Glb_Inter_HOST_LDAP_Link_tbl.Attach_Inprog
	set Glb_Inter_HOST_LDAP_Link_tbl.Link_Instance =
		data_request!get_instance(Inter_Host_DR_Dataview_Name)

	if(Glb_Inter_HOST_LDAP_Link_tbl.Link_Instance == 0)
	then
		incr Glb_Inter_HOST_LDAP_Link_tbl.Retried_Times
		if Glb_Inter_HOST_LDAP_Link_tbl.Retried_Times >= LDAP_Link_Retry_Limit + 1
		then
			set Glb_Inter_HOST_LDAP_Link_tbl.Link_Status = DR_P_Unavailable
			set Glb_Inter_HOST_LDAP_Link_tbl.Last_Attach_Time = clock()
		else
			set Glb_Inter_HOST_LDAP_Link_tbl.Link_Status = DR_T_Unavailable
		end if
	else
		set Glb_Inter_HOST_LDAP_Link_tbl.Link_Status = DR_Available
		reset Glb_Inter_HOST_LDAP_Link_tbl.Retried_Times
	end if

	next event Attach_Inter_HOST_Dataview_Result
	return

end event data_request!attach_user_completed

event data_request!attach_user_failed
	#Send om if attach failed
	set Glb_GSL_Error_Return = "Data Request attach failed"
	send_om(
	        msg_id = counter("30" : "702"),  #SP28.16 RDAF729606
		msg_class = GSL_Craft_Assert_Message_Class,
		title = "REPT SPA MAINTENANCE ASSERT=702, SPA=EPPSM",
		poa = GSL_Assert_Priority,
		message = "Internal System Error - " : Glb_GSL_Error_Return,
		message2 = ""
		)
	# in case the link table is interrupt by other call, set the index again.
	set Glb_Inter_HOST_LDAP_Link_tbl.index = Member_SCP_Name

	reset Glb_Inter_HOST_LDAP_Link_tbl.Attach_Inprog
	incr Glb_Inter_HOST_LDAP_Link_tbl.Retried_Times
	if Glb_Inter_HOST_LDAP_Link_tbl.Retried_Times >= LDAP_Link_Retry_Limit + 1
	then
		set Glb_Inter_HOST_LDAP_Link_tbl.Link_Status = DR_P_Unavailable
		set Glb_Inter_HOST_LDAP_Link_tbl.Last_Attach_Time = clock()
	else
		set Glb_Inter_HOST_LDAP_Link_tbl.Link_Status = DR_T_Unavailable
	end if

	next event Attach_Inter_HOST_Dataview_Result
	return

end event data_request!attach_user_failed

#----------------------------------------------------
# Event:	data_request!detach_user_completed
#
# Description:	after detaching successfully, just
#		attach the dataview
#----------------------------------------------------
event data_request!detach_user_completed
	next event Attach_Inter_HOST_Dataview
	return
end event data_request!detach_user_completed

#----------------------------------------------------
# Event:        data_request!detach_user_completed
#
# Description:  after detaching failed, just
#               attach the dataview
#----------------------------------------------------
event data_request!detach_user_failed
	next event Attach_Inter_HOST_Dataview
	return
end event data_request!detach_user_failed

#----------------------------------------------------
# Event:        data_request!read_completed
#
# Description:  after receiving responce from member, 
#               end call
#----------------------------------------------------
event data_request!read_completed
	set Glb_Temp_Flag_1 = Incr_Data_Request_Completed_Counter(@.data.result_code)
	#VzW Feature 72139
	if @.data.result_code == "00"
	then
		set LDAP_Res_String = @.data.return_data
		set Upd_Counter_Bro_Para_Result.Result_Code = GRC_Success
	elif @.data.result_code == "02" && !Already_Query_With_Healing
	then
		set Already_Query_With_Healing
		set Upd_Counter_Bro_Para_Result.Result_Code = GRC_Query_With_Healing
	elif @.data.result_code == "03"
	then
		set Upd_Counter_Bro_Para_Result.Result_Code = GRC_Duplicated_Message
	else
		set Upd_Counter_Bro_Para_Result.Result_Code = GRC_Failed
	end if
	if @.data.result_code != "02"
	then
		reset Already_Query_With_Healing
	end if

	next event Upd_Counter_Bro_Para_Result
	return
end event data_request!read_completed

#----------------------------------------------------
# Event:        data_request!read_failed
#
# Description:  after receiving responce from member, 
#               end call
#----------------------------------------------------
event data_request!read_failed
	incr Data_Req_Rec_Fail_Msg_Num
	if Data_Req_To_Des_Flag
	then
		reset Data_Req_To_Des_Flag
		test Member_Group_ID_Type
		case "S"
			incr Data_Req_Rec_Fail_Msg_Num_Broadcast
		case "G"
			incr Data_Req_Rec_Fail_Msg_Num_U_Or_Q
		end test
	end if
	# SP28.10 feature 73939
	if @.failure_reason == e_busy
	then
		set Upd_Counter_Bro_Para_Result.Result_Code = GRC_Busy
        	next event Upd_Counter_Bro_Para_Result
        	return
	end if
	set Glb_Temp_String1 = data_request!get_name(@.instance)

        #SP28.16 RDAF729606
        Parse_Object(",", string(Glb_Ntwk_Msg_Assert_Title))
        if Glb_Parse_Temp_Count > 0
        then
        	set Glb_Temp_String_Parsed = map(Glb_Parsed,
        		"abcdefghijklmnopqrstuvwxzyABCDEFGHIJKLMNOPQRSTUVWXYZ= ", "")
        else
        	set Glb_Temp_String_Parsed = "000"
        end if
			
	send_om(
	        msg_id = counter("30" : Glb_Temp_String_Parsed),
		msg_class = GSL_Internal_Assert_Message_Class,
		poa = GSL_Internal_Assert_Priority,
		title = Glb_Ntwk_Msg_Assert_Title,
		message = "read fail when updata counter or broadcast" :
		"\n dataview = " : Glb_Temp_String1 :
		"\n failure reason = " : string(@.failure_reason),
		message2 = "\nCall Instance ID = " : string(call_index()) :
		"\nScenario Location = data_request!read_failed"
		)
	set Glb_Temp_String2 = substring(Glb_Temp_String1, 1, (length(Glb_Temp_String1) - 13))
	if element_exists(Glb_Inter_HOST_LDAP_Link_tbl, Glb_Temp_String2)
	then
		set Glb_Inter_HOST_LDAP_Link_tbl.index = Glb_Temp_String2
		set Glb_Temp_Counter_1 = Glb_Inter_HOST_LDAP_Link_tbl.Link_Instance
		reset Glb_Inter_HOST_LDAP_Link_tbl.Link_Instance
		set Glb_Inter_HOST_LDAP_Link_tbl.Link_Status = DR_T_Unavailable
		if @.failure_reason == e_local_release && !Already_Attach_User_Flag &&
			!Glb_Inter_HOST_LDAP_Link_tbl.Attach_Inprog &&
			(Glb_Inter_HOST_LDAP_Link_tbl.Retried_Times < LDAP_Link_Retry_Limit + 1 ||
			(Glb_Inter_HOST_LDAP_Link_tbl.Retried_Times >= LDAP_Link_Retry_Limit + 1 &&
			LDAP_Link_Failover_Period > 0 &&
			clock() > (LDAP_Link_Failover_Period * 60 + Glb_Inter_HOST_LDAP_Link_tbl.Last_Attach_Time)))
		then
			set Already_Attach_User_Flag
			set Check_LDAP_Link_Return_Point = GCF_Upd_Counter_Broadcast_Para
			data_request!detach_user(instance = Glb_Temp_Counter_1,
				tenths_timeout = 40)
			return
		end if 
	end if 

	# There is a instance in INTER_eCS_COMM waiting for response so can not end call directly 
	set Upd_Counter_Bro_Para_Result.Result_Code = GRC_Failed
	next event Upd_Counter_Bro_Para_Result
	return
end event data_request!read_failed

event Attach_Inter_HOST_Dataview_Result

	reset Glb_Inter_HOST_LDAP_Link_tbl.Attach_Inprog

	if Glb_Inter_HOST_LDAP_Link_tbl.Link_Status == DR_T_Unavailable ||
		Glb_Inter_HOST_LDAP_Link_tbl.Link_Status == DR_P_Unavailable
	then
		reset Request_Inter_HOST_LDAP_Link_Check_Result.Available
	else
		set Request_Inter_HOST_LDAP_Link_Check_Result.Available
	end if

	next event Request_Inter_HOST_LDAP_Link_Check_Result
	return

end event Attach_Inter_HOST_Dataview_Result

event Request_Inter_HOST_LDAP_Link_Check_Result
	if @.Available
	then
		if Check_LDAP_Link_Return_Point == GCF_Upd_Counter_Broadcast_Para #VzW 72139
		then
			reset Check_LDAP_Link_Return_Point
			next event Upd_Counter_Bro_Para_Continue
			return
		end if
	else
		if Check_LDAP_Link_Return_Point == GCF_Upd_Counter_Broadcast_Para
		then
			reset Check_LDAP_Link_Return_Point
			set Upd_Counter_Bro_Para_Result.Result_Code = GRC_Failed
			next event Upd_Counter_Bro_Para_Result
			return
		end if
	end if

end event Request_Inter_HOST_LDAP_Link_Check_Result
# VzW 72138 end

event Request_CDB_RTDB_Retrieve
	if !GLB_CDB_RTDB_Attached
	then
		set Glb_Temp_String1 = "CDB_RTDB"	#rtdb name
		set Glb_Temp_String2 = "attach"	#operation name
                #SP28.16 RDAF729606
                Parse_Object(",", string(Glb_RTDB_Operation_Assert_Title))
                if Glb_Parse_Temp_Count > 0
                then
                	set Glb_Temp_String_Parsed = map(Glb_Parsed,
                		"abcdefghijklmnopqrstuvwxzyABCDEFGHIJKLMNOPQRSTUVWXYZ= ", "")
                else
                	set Glb_Temp_String_Parsed = "000"
                end if
			
		send_om(
	                msg_id = counter("30" : Glb_Temp_String_Parsed),
			msg_class = GSL_Internal_Assert_Message_Class,
			poa = GSL_Internal_Assert_Priority,
			title = Glb_RTDB_Operation_Assert_Title,
			message =	"Internal System Error - ":Glb_Temp_String2:" ":Glb_Temp_String1:" failed." ,
			message2 = "\nCall Instance ID = " : string(BCI_Service_Instance_ID) :
			"\nScenario Location = Request_CDB_RTDB_Retrieve"
		)
		reset Request_CDB_RTDB_Retrieve_Result.Success
		next event Request_CDB_RTDB_Retrieve_Result
		return
	end if
	set CDB_RTDB_Record1.CDB_Key = @.key_index
	reset CDB_RTDB_Flag
	set CDB_RTDB_Flag.CDB_Key
	CDB_RTDB!search(instance = GLB_CDB_RTDB_Instance,
		data = CDB_RTDB_Record1,
		present = CDB_RTDB_Flag,
		exact = RTDB_Exact_Match,
		max_records =CDB_RTDB_Max_Records
		)
	return
end event Request_CDB_RTDB_Retrieve

event CDB_RTDB!search_result
	set CDB_RTDB_Record1 = @.data
	test Retrieve_CD_RTDB_Step
	case Req_Qry_Sec_Acc_Hier_Info
		set Glb_Temp_String2 = CDB_RTDB_Record1.CDB_Key
		Parse_Object(":", Glb_Temp_String2)
		reset Top_Has_Found
		if !element_exists(Secondary_Acc_tbl, Glb_Remainder)
		then
			insert into Secondary_Acc_tbl at Glb_Remainder
		end if
		if CDB_RTDB_Record1.Top_Account_Indicator
		then
			set Top_Has_Found
		end if
		if !Top_Has_Found
		then
			incr Group_ID_Pos
			set Group_ID_List_rec.Group_ID = Glb_Remainder
			insert Group_ID_List_rec into Group_ID_List_tbl at Group_ID_Pos
		end if
		return
	case Req_Qry_Sec_Acc_Hier_Info_To_Top
		set Glb_Temp_String2 = CDB_RTDB_Record1.CDB_Key
		Parse_Object(":", Glb_Temp_String2)
		reset Top_Has_Found
		set Group_ID = Glb_Remainder
		if !element_exists(Secondary_Acc_tbl, Group_ID)
		then
			insert into Secondary_Acc_tbl at Group_ID
		else
			set Top_Has_Found
		end if
		if CDB_RTDB_Record1.Top_Account_Indicator
		then
			set Top_Has_Found
		end if
		return
	case any(Req_Primary_Group_Exist,Req_Qry_Hier_Info_For_Acct,Req_Group_Info)
	 	return
	case P_S_Req_Group_Info
		set Glb_Temp_String2 = CDB_RTDB_Record1.CDB_Key
		Parse_Object(":", Glb_Temp_String2)
		if Glb_Remainder != "" && !Group_Info_Length_Exceed
		then
			set Group_ID = Group_IDs:Glb_Remainder:","
			if length(Group_ID) > Glb_Group_IDs_Max_Length
			then
				set S_P!Request_Group_Information_Result.Length_Limit_Exceed
				set Group_Info_Length_Exceed
				return
			end if
			set Group_IDs = Group_IDs:Glb_Remainder:","
		end if
		return
	case P_S_Req_Group_Info_Online
		set Glb_Temp_String1 = CDB_RTDB_Record1.CDB_Key
		Parse_Object(":", Glb_Temp_String1)
		reset Group_ID_List_rec
		if CDB_RTDB_Record1.Top_Account_Indicator
		then
			incr Branch_Number
			set Group_IDs = Group_IDs : "H" : string(Branch_Number) : "="
			if CDB_RTDB_Record1.Billing_Responsibility_Indicator
			then
				set BR_String = ",BR=" : Glb_Remainder
				set Next_String = Glb_Remainder : BR_String : ";"
			else
				set Next_String = Glb_Remainder : ";"
			end if
			set Group_IDs = Group_IDs : Next_String
		else 
			incr Group_ID_Pos
			if CDB_RTDB_Record1.Billing_Responsibility_Indicator
			then
				set Group_ID_List_rec.BR_flag
			end if
			set Group_ID_List_rec.Group_ID = Glb_Remainder
			insert Group_ID_List_rec into Group_ID_List_tbl at Group_ID_Pos
			return
		end if
	case P_S_Req_Group_Info_Online_To_Top
		return
	case Upd_GPRSSIM_For_Online		#76541	
		set Glb_Temp_String2 = CDB_RTDB_Record1.CDB_Key
		Parse_Object(":", Glb_Temp_String2)
		
		if Glb_Remainder != ""
		then
			set Group_ID = Glb_Remainder
			incr Account_ID_Pos
			insert into Account_ID_List_tbl at Account_ID_Pos
			set Account_ID_List_tbl.Account_ID = Glb_Remainder
			set Total_Account_Number = Account_ID_Pos
		end if
		if CDB_RTDB_Record1.Top_Account_Indicator || Glb_Remainder == ""
		then
			set Top_Has_Found
		end if
		return
	end test
end event CDB_RTDB!search_result

event CDB_RTDB!search_completed
	if Retrieve_CD_RTDB_Step == Upd_GPRSSIM_For_Online
	then
		if @.reason == e_a_okay && !Top_Has_Found
		then
			set Request_CDB_RTDB_Retrieve.key_index = Group_ID : ":"
			set CDB_RTDB_Max_Records = 1
			reset RTDB_Exact_Match
			next event Request_CDB_RTDB_Retrieve
			return
		else
			set Request_CDB_RTDB_Retrieve_Result.Success
			next event Request_CDB_RTDB_Retrieve_Result
			return
		end if 
	else
	if @.reason == any(e_a_okay,e_max_records_exceeded)
	then	
		set Request_CDB_RTDB_Retrieve_Result.Success
		next event Request_CDB_RTDB_Retrieve_Result
		return
	elif @.reason == e_tuple_not_found
	then
		test Retrieve_CD_RTDB_Step
		case Req_Qry_Sec_Acc_Hier_Info
			set Account_Number = 1
			reset Hierarchy_Structure_tbl[]
			next event Req_Qry_Account_Hier_Info
			return
		case Req_Qry_Sec_Acc_Hier_Info_To_Top
			next event Req_Sec_Account_Hier_To_Top
			return
		case Req_Primary_Group_Exist
			set CDB_RTDB_Record1 = @.data
			set Glb_Temp_String2 = CDB_RTDB_Record1.CDB_Key
			Parse_Object(":", Glb_Temp_String2)
			set Hierarchy_Structure_tbl.Account_List_rec.Account_List_tbl[] = Branch_Acc_List_tbl[]
			set Hierarchy_Structure_tbl.Level_Number = Search_Level
			if Query_Group_Operation != "1"
			then
				set Hierarchy_Structure_tbl.SCP_Name = Glb_Parsed
			end if	
			incr Account_Number
			next event Req_Qry_Account_Hier_Info
			return
		case Req_Qry_Hier_Info_For_Acct
			set Hierarchy_Structure_tbl.Level_Number = Search_Level
			set Hierarchy_Structure_tbl.Account_List_rec.Account_List_tbl[] =
				Branch_Acc_List_tbl[]
			incr Glb_Service_Measurement_Rec.Number_of_Successful_cDB_Accesses
			if Sponsoring_Account_ID != ""
			then
				set Retrieve_GPRSSIM_For = RGR_Sponsoring_Account
				set GPRSSIM_Retrieve.Key_Index = Sponsoring_Account_ID
				next event GPRSSIM_Retrieve
				return
			else
				next event Determine_Hierarchy_Complete_1
				return
			end if
		case Req_Group_Info
			set Intra_Group_Indicator = Intra_Group_Indicator : "0" : ","
			if Query_Group_Operation == any("0", "2")
			then
				set Retrieve_GPRSSIM_For = RGR_Intra_Group
				set GPRSSIM_Retrieve.Key_Index = Account_ID_List_tbl.Account_ID
				next event GPRSSIM_Retrieve
				return
			end if
			incr Account_ID_Pos
			next event Req_Query_Group_Info_From_CDB_RTDB
			return
		case any (P_S_Req_Group_Info, P_S_Req_Group_Info_Online)
			reset Group_IDs
			set S_P!Request_Group_Information_Result.Account_List = Group_IDs
			send(to = Inter_eCS_COMM_FSM_Call_Index, event = S_P!Request_Group_Information_Result, ack = false)
			next event Service_Terminate_Call 
			return
		case P_S_Req_Group_Info_Online_To_Top
			set Group_ID = substring(Group_ID, 1, length(Group_ID) - 1)
			if BR_Has_Found
			then
				set Glb_Temp_String1 = Group_ID : BR_String : ";"
			else
				set Glb_Temp_String1 = Group_ID : ";"
			end if
			if length(Glb_Temp_String1) > Glb_Group_IDs_Max_Length
			then
				set Group_IDs = substring(Group_IDs, 1, length(Group_IDs) - 1)
				set S_P!Request_Group_Information_Result.Length_Limit_Exceed
				set S_P!Request_Group_Information_Result.Account_List = Group_IDs
				
				send(to = Inter_eCS_COMM_FSM_Call_Index, event = S_P!Request_Group_Information_Result, ack = false)
				next event Service_Terminate_Call
				return
			else
				set Group_ID = Glb_Temp_String1
				set Group_IDs = Group_ID				
			end if				
			next event P_S_Req_Group_Info_To_Top
			return
		end test
	else
		set Glb_GSL_Error_Return = "CDB_RTDB read failed"
		set Glb_Temp_String1 = "CDB_RTDB"        #rtdb name
		set Glb_Temp_String2 = "read"           #operation name
                #SP28.16 RDAF729606
                Parse_Object(",", string(Glb_RTDB_Operation_Assert_Title))
                if Glb_Parse_Temp_Count > 0
                then
                	set Glb_Temp_String_Parsed = map(Glb_Parsed,
                		"abcdefghijklmnopqrstuvwxzyABCDEFGHIJKLMNOPQRSTUVWXYZ= ", "")
                else
                	set Glb_Temp_String_Parsed = "000"
                end if
			
		 send_om(
	                msg_id = counter("30" : Glb_Temp_String_Parsed),
			msg_class = GSL_Internal_Assert_Message_Class,
			title = Glb_RTDB_Operation_Assert_Title,
			poa = GSL_Internal_Assert_Priority,
			message = "Internal System Error - ":Glb_Temp_String2:" ":Glb_Temp_String1:" failed.",
			message2 =
			"\nSubscriber ID = " :
			"\nCall Instance ID = " : string(call_index()) :
			"\nScenario Location = CDB_RTDB!search_completed" :
			"\nFailure Reason = " : string(@.reason)
		)
		reset Request_CDB_RTDB_Retrieve_Result.Success
		next event Request_CDB_RTDB_Retrieve_Result
		return
	end if
	end if

end event CDB_RTDB!search_completed


event Request_CDB_RTDB_Retrieve_Result
	if @.Success
	then
		test Retrieve_CD_RTDB_Step
		case Req_Qry_Sec_Acc_Hier_Info
			set Total_Group_IDs_Length = table_length(Group_ID_List_tbl)
			if Total_Group_IDs_Length == 0
			then
				set Account_Number = 1
				reset Hierarchy_Structure_tbl[]
				next event Req_Qry_Account_Hier_Info
				return
			else
				reset Group_ID_Pos
				next event Req_Sec_Account_Hier_To_Top
				return
			end if
		case Req_Qry_Sec_Acc_Hier_Info_To_Top
			if !Top_Has_Found
			then
				set CDB_RTDB_Max_Records = 1
				reset RTDB_Exact_Match
				set Retrieve_CD_RTDB_Step = Req_Qry_Sec_Acc_Hier_Info_To_Top
				set Request_CDB_RTDB_Retrieve.key_index = Group_ID : ":"
				next event Request_CDB_RTDB_Retrieve
				return
			else
				next event Req_Sec_Account_Hier_To_Top
				return
			end if

		case Req_Primary_Group_Exist
			set Hierarchy_Structure_tbl.present
			Parse_Object(":",CDB_RTDB_Record1.CDB_Key)  
			  
			incr Search_Level
			insert into Branch_Acc_List_tbl at Search_Level
			set Branch_Acc_List_tbl.Account_ID = Glb_Remainder
			if !BR_Has_Found && CDB_RTDB_Record1.Billing_Responsibility_Indicator
			then
				set BR_Has_Found				
				set Hierarchy_Structure_tbl.BR_Level = Search_Level
			end if
			if !Relation_Has_Found && Query_Group_Operation != "2"&& Secondary_Account_ID != ""
			then
				if element_exists(Secondary_Acc_tbl, Glb_Remainder)
				then
					set Relation_Has_Found
					set Hierarchy_Structure_tbl.Relation_Level = Search_Level
				end if 
			end if
			if CDB_RTDB_Record1.Top_Account_Indicator
			then
				set Top_Has_Found
				set Hierarchy_Structure_tbl.Level_Number=Search_Level
				if Query_Group_Operation != "1"
				then
					set Hierarchy_Structure_tbl.SCP_Name = Glb_Remainder
				end if
			end if
			if Top_Has_Found
			then
				set Hierarchy_Structure_tbl.Account_List_rec.Account_List_tbl[] = Branch_Acc_List_tbl[]
				incr Account_Number
				next event Req_Qry_Account_Hier_Info
				return
			end if
			set Retrieve_CD_RTDB_Step = Req_Primary_Group_Exist
			set Request_CDB_RTDB_Retrieve.key_index = Glb_Remainder:":"
			set CDB_RTDB_Max_Records = 1
			reset RTDB_Exact_Match 
			next event Request_CDB_RTDB_Retrieve
			return
		case Req_Qry_Hier_Info_For_Acct
			set Glb_Temp_String2 = CDB_RTDB_Record1.CDB_Key
			Parse_Object(":", Glb_Temp_String2)
			if CDB_RTDB_Record1.Top_Account_Indicator
			then
				incr Search_Level
				insert into Branch_Acc_List_tbl at Search_Level
				set Branch_Acc_List_tbl.Account_ID = Glb_Remainder
				set Hierarchy_Structure_tbl.Level_Number = Search_Level
				set Top_Has_Found
			end if
			if !Top_Has_Found
			then
				incr Search_Level
				insert into Branch_Acc_List_tbl at Search_Level
				set Branch_Acc_List_tbl.Account_ID = Glb_Remainder
				set Retrieve_CD_RTDB_Step = Req_Qry_Hier_Info_For_Acct
				set Request_CDB_RTDB_Retrieve.key_index = Glb_Remainder : ":"
				set CDB_RTDB_Max_Records = 1
				reset RTDB_Exact_Match
				next event Request_CDB_RTDB_Retrieve
				return
			end if
			set Hierarchy_Structure_tbl.Account_List_rec.Account_List_tbl[] =Branch_Acc_List_tbl[]
			incr Glb_Service_Measurement_Rec.Number_of_Successful_cDB_Accesses
			if Sponsoring_Account_ID != ""
			then
				set Retrieve_GPRSSIM_For = RGR_Sponsoring_Account
				set GPRSSIM_Retrieve.Key_Index = Sponsoring_Account_ID
				next event GPRSSIM_Retrieve
				return
			else
				next event Determine_Hierarchy_Complete_1
				return
			end if
		case Req_Group_Info
			set Intra_Group_Indicator = Intra_Group_Indicator : "1" : ","
			if Query_Group_Operation == any("0", "2")
			then
				set Retrieve_GPRSSIM_For = RGR_Intra_Group
				set GPRSSIM_Retrieve.Key_Index = Account_ID_List_tbl.Account_ID
				next event GPRSSIM_Retrieve
				return
			end if
			incr Account_ID_Pos
			next event Req_Query_Group_Info_From_CDB_RTDB
			return 
		case P_S_Req_Group_Info
			# remove the last "," 
			if Group_IDs != ""
			then
				set Group_IDs = substring(Group_IDs, 1, length(Group_IDs) - 1)
			end if
			set S_P!Request_Group_Information_Result.Account_List = Group_IDs
			send(to = Inter_eCS_COMM_FSM_Call_Index, event = S_P!Request_Group_Information_Result, ack = false)
			next event Service_Terminate_Call
			return
		case P_S_Req_Group_Info_Online
			set Total_Group_IDs_Length = table_length(Group_ID_List_tbl)
			reset Group_ID_Pos
			next event P_S_Req_Group_Info_To_Top
			return
		case P_S_Req_Group_Info_Online_To_Top
			set Glb_Temp_String2 = CDB_RTDB_Record1.CDB_Key
			Parse_Object(":", Glb_Temp_String2)
			if Glb_Remainder != ""
			then
				if !BR_Has_Found && CDB_RTDB_Record1.Billing_Responsibility_Indicator
				then
					set BR_Has_Found
					set BR_String = ",BR=" : Glb_Remainder
				end if
				if CDB_RTDB_Record1.Top_Account_Indicator
				then
					set Top_Has_Found
					if BR_Has_Found
					then
						set Next_String = Glb_Remainder : BR_String :";"
					else
						set Next_String = Glb_Remainder : ";"
					end if
				else
					set Next_String = Glb_Remainder : ":"
				end if
				set Group_ID = Group_ID : Next_String
			else
				set Top_Has_Found
				set Group_IDs =
					substring(Group_IDs, 1, length(Group_IDs) - 1)
				if BR_Has_Found
				then
					set Group_IDs = Group_IDs : BR_String : ";"
				else
					set Group_IDs = Group_IDs : ";"
				end if
				set Group_ID = Group_IDs
			end if
			if Top_Has_Found
			then
				if length(Group_ID) > Glb_Group_IDs_Max_Length
				then
					set Group_IDs = substring(Group_IDs, 1, length(Group_IDs) - 1)
					set S_P!Request_Group_Information_Result.Length_Limit_Exceed
					set S_P!Request_Group_Information_Result.Account_List = Group_IDs
					send(to = Inter_eCS_COMM_FSM_Call_Index, event = S_P!Request_Group_Information_Result, ack = false)
					next event Service_Terminate_Call
					return
				else
					set Group_IDs = Group_ID
				end if
				next event P_S_Req_Group_Info_To_Top
				return
			else
				set CDB_RTDB_Max_Records = 1
				reset RTDB_Exact_Match
				set Retrieve_CD_RTDB_Step = P_S_Req_Group_Info_Online_To_Top
				set Request_CDB_RTDB_Retrieve.key_index = Glb_Remainder : ":"
				next event Request_CDB_RTDB_Retrieve
				return
			 end if
		case Upd_GPRSSIM_For_Online		#76541
			set Account_ID_Pos = 1
			next event Upd_GPRSSIM_For_Online_Hier
			return
		end test
	else
		test Retrieve_CD_RTDB_Step
		case any(P_S_Req_Group_Info,P_S_Req_Group_Info_Online,P_S_Req_Group_Info_Online_To_Top)
			reset Hierarchy_Structure_tbl[]
			reset S_P!Request_Group_Information_Result
			send(to = Inter_eCS_COMM_FSM_Call_Index,
			event = S_P!Request_Group_Information_Result,
			ack = false)
			next event Service_Terminate_Call
			return
		other
			reset Hierarchy_Structure_tbl[]
			next event Determine_Hierarchy_Complete_1
			return
		end test
	end if
			
end event Request_CDB_RTDB_Retrieve_Result
}\
behavior Event_Code {
}\
behavior Server_Default_Event_Code     {
#-----------------------------------------------------------------
# event: Get_Access_Index
#
# Description:
# -----------------------------------------------------------
event Get_Access_Index
	set Glb_SERVER_Adm_Customer_Index = routing_string!lookup(Svr_Adm_Access_Key)
	if Glb_SERVER_Adm_Customer_Index == 0
	then
		schedule(clock = clock() + 3,
			event = Get_Access_Index)
	else
		print("Glb_SERVER_Adm_Customer_Index =", Glb_SERVER_Adm_Customer_Index)
	end if
	end_call
	return

end event Get_Access_Index
#-----------------------------------------------------------------
# event: Service_Measurement_Handling
#
# Description: Generate service measurement in server adm fsm
#
#------------------------------------------------------------------------
event Service_Measurement_Handling
	set Service_Meas1.Successful_cDB_Accesses =
		Service_Meas1.Successful_cDB_Accesses +
		@.Content.Number_of_Successful_cDB_Accesses
	set Service_Meas1.Unsuccessful_cDB_Accesses =
		Service_Meas1.Unsuccessful_cDB_Accesses +
		@.Content.Number_of_Unsuccessful_cDB_Accesses
        #R28.7 73494 & 72850
        set Service_Meas1.Successful_Local_Index_Query =
                Service_Meas1.Successful_Local_Index_Query +
                @.Content.Successful_Local_Index_Query
        set Service_Meas1.Successful_SelfLearning_Attempt =        
                Service_Meas1.Successful_SelfLearning_Attempt +
                @.Content.Successful_SelfLearning_Attempt
        set Service_Meas1.Failed_SelfLearning_Attempt =
                Service_Meas1.Failed_SelfLearning_Attempt +
                @.Content.Failed_SelfLearning_Attempt
        set Service_Meas1.Successful_SelfHealing_Attempt =
                Service_Meas1.Successful_SelfHealing_Attempt +
                @.Content.Successful_SelfHealing_Attempt
        set Service_Meas1.Failed_SelfHealing_Attempt =
                Service_Meas1.Failed_SelfHealing_Attempt +
                @.Content.Failed_SelfHealing_Attempt
        set Service_Meas1.Received_Insert_Via_Broadcast =
                Service_Meas1.Received_Insert_Via_Broadcast +
                @.Content.Received_Insert_Via_Broadcast
        set Service_Meas1.Received_Delete_Via_Broadcast =
                Service_Meas1.Received_Delete_Via_Broadcast +
                @.Content.Received_Delete_Via_Broadcast
        set Service_Meas1.Received_Update_Via_Broadcast =
                Service_Meas1.Received_Update_Via_Broadcast +
                @.Content.Received_Update_Via_Broadcast
        set Service_Meas1.Failed_Insert_Due_Sub_Exist =
                Service_Meas1.Failed_Insert_Due_Sub_Exist +
                @.Content.Failed_Insert_Due_Sub_Exist
        set Service_Meas1.Insert_Converted_To_Upd_Due_Datachg =
                Service_Meas1.Insert_Converted_To_Upd_Due_Datachg +
                @.Content.Insert_Converted_To_Upd_Due_Datachg
        set Service_Meas1.Timeout_Self_Learning_Attempts =
                Service_Meas1.Timeout_Self_Learning_Attempts +
                @.Content.Timeout_Self_Learning_Attempts
        set Service_Meas1.Timeout_Self_Healing_Attempts =
                Service_Meas1.Timeout_Self_Healing_Attempts +
                @.Content.Timeout_Self_Healing_Attempts
        set Service_Meas1.Suppressed_Self_Learning_For_Prev_F =
                Service_Meas1.Suppressed_Self_Learning_For_Prev_F +
                @.Content.Suppressed_Self_Learning_For_Prev_F	
        set Service_Meas1.UnSuccessful_GPRSSIM_Query =
                Service_Meas1.UnSuccessful_GPRSSIM_Query +
                @.Content.UnSuccessful_GPRSSIM_Query
        # SP28.10 feature 73939
        set Service_Meas1.LDAP_GBrdC_Flt_By_OLC = 	# 17
          	Service_Meas1.LDAP_GBrdC_Flt_By_OLC +
               	@.Content.LDAP_GBrdC_Flt_By_OLC
        set Service_Meas1.LDAP_MUsg_Flt_By_OLC =	# 18
               	Service_Meas1.LDAP_MUsg_Flt_By_OLC +
              	@.Content.LDAP_MUsg_Flt_By_OLC
        set Service_Meas1.LDAP_IdxReq_Flt_By_OLC =	# 19
               	Service_Meas1.LDAP_IdxReq_Flt_By_OLC +
               	@.Content.LDAP_IdxReq_Flt_By_OLC
        set Service_Meas1.LDAP_HierReq_Flt_By_OLC =	# 20
               	Service_Meas1.LDAP_HierReq_Flt_By_OLC +
               	@.Content.LDAP_HierReq_Flt_By_OLC
        end_call
end event Service_Measurement_Handling

#ih_cr31280
#----------------------------------------------------------------------
# event: 	Clt_Svr!Lock_GPRSSIM_Op
#
# Description:	This event is used to handle lock GPRSSIM operation.
#
#----------------------------------------------------------------------
event Clt_Svr!Lock_GPRSSIM_Op
	if !element_exists(Glb_GPRSSIM_Op_Locked_tbl, @.Key)
	then
		insert into Glb_GPRSSIM_Op_Locked_tbl at @.Key
		reset Svr_Clt!Lock_GPRSSIM_Op_Result.Success
	else
		set Svr_Clt!Lock_GPRSSIM_Op_Result.Success
	end if

	xp_send_response(to = xp_dest_query(),
		event = Svr_Clt!Lock_GPRSSIM_Op_Result,
		ack = false)
	end_call
end event Clt_Svr!Lock_GPRSSIM_Op

#----------------------------------------------------------------------
# event:        Clt_Svr!Unlock_GPRSSIM_Op
#
# Description:  This event is used to handle unlock GPRSSIM operation.
#
#----------------------------------------------------------------------
event Clt_Svr!Unlock_GPRSSIM_Op
	if element_exists(Glb_GPRSSIM_Op_Locked_tbl, @.Key)
	then
		delete from Glb_GPRSSIM_Op_Locked_tbl at @.Key
	end if
	end_call
end event Clt_Svr!Unlock_GPRSSIM_Op

}\
