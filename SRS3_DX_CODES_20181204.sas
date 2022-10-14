*******************************************************************************;
* PROGRAM DETAILS                                                             *;
*   Filename: SRS3_DX_CODES_20181204.sas                                      *;
*   Location: G:\CTRHS\MHRN\SRS3_PredictingSuicide\Programming\Reference      *;
*   Purpose:  Compile and format various Dx code lists for use in SRS3        *;
*   Author:   Rebecca Ziebell (rebecca.a.ziebell@kp.org)                      *;
*   Updated:  December 4, 2018                                                *;
*******************************************************************************;
* UPDATE HISTORY                                                              *;
*   20180402  Initial version finalized after review from Greg Simon          *;
*   20180417  Updated to include SUB flag to denote subsequent encounters in  *;
*             ICD-10 injury/poisoning chapters. Removed GEN from MULTI/UNCAT  *;
*             calculated variables, choosing instead to focus on standard     *;
*             MHRN subcategories (although GEN will stay in code list for     *;
*             possible use). Removed SRS3_DENOM/_COVAR flags as these may yet *;
*             change (and can be calculated at the point of use).             *;
*   20180531  Added SUB/SEQ flags to X & Y codes.                             *;
*   20181204  Appended code to correct issues with alcohol/drug dependence in *;
*             remission codes that had NOT been removed from MEN/ALC/DRU      *;
*             code sets. Also added note that CODE+DESC is primary key and    *;
*             relabeled MEN to note that it reflects our "typical MHRN"       *;
*             definition of what constitutes a MH disorder for anlaysis.      *;
*             Jump to line ~700 for appended corrections.                     *;
*******************************************************************************;

%include "\\home\&sysuserid\remoteactivate.sas";

%let root = \\groups\data\CTRHS\MHRN\SRS3_PredictingSuicide\Programming\Reference;

%let fn = SRS3_DX_CODES;

proc datasets kill lib=work memtype=data nolist;
quit;

%macro dsdelete(dslist /* pipe-delimited list */);
proc sql;
  %do ds = 1 %to %sysfunc(countw(&dslist, |));
    %let dsname = %scan(&dslist, &ds, |);
    %if %sysfunc(exist(&dsname)) = 1 %then %do;
        drop table &dsname;
    %end;
  %end;
quit;
%mend dsdelete;

%macro head(ds=&syslast, n=10);
  proc print data=&ds (obs=&n) heading=h width=min;
    title "First &n observations of %upcase(&ds)";
    footnote;
  run;

  title;
%mend head;

%macro tail(ds=&syslast, n=10);
  %local nobs;

  proc sql noprint;
    select count(*) into :nobs from &ds;
  quit;

  proc print data=&ds (firstobs=%eval(&nobs - &n + 1)) heading=h width=min;
    title "Last &n observations of %upcase(&ds)";
    footnote;
  run;

  title;
%mend tail;

options errors=0 formchar="|----|+|---+=|-/\<>*" mprint nodate nofmterr
  nomlogic nonumber nosymbolgen orientation=portrait
;

title;

footnote;

%let filedate = %sysfunc(today(), yymmddn8.);

%let dispdate = %sysfunc(today(), mmddyys10.);

resetline;

*******************************************************************************;
* ICD-10                                                                      *;
*******************************************************************************;

*------------------------------------------------------------------------------;
* Read in all available ICD-10-CM code lists, compile, and deduplicate. This   ;
* will ensure that we have historical codes available for studies that cross   ;
* multiple years.                                                              ;
*------------------------------------------------------------------------------;
%let prefix10 = https://www.cms.gov/Medicare/Coding/ICD10/Downloads;

%macro cmsicd10(yy, zipfile, zipmem);
  %dsdelete(cms&yy)

  %let ziploc = %sysfunc(getoption(work))\datafile.zip;

  filename download "&ziploc";

  proc http method='GET'
    out=download
    proxyhost="proxy.ghc.org"
    proxyport=8080
    url="&prefix10/&zipfile"
  ;
  run;

  filename inzip zip "&ziploc";

  data cms&yy;
    infile inzip("&zipmem") truncover;
    input @1 CODE $7. @9 DESC $256.; 
    code = upcase(code);
    desc = upcase(desc);
    length CMS&yy 3;
    CMS&yy = 1;
    label cms&yy="Code+desc in 20&yy CMS release (1/0)";
    if code in: ('F', 'S', 'T') /* mental health, injury & poisoning chapters */
      or 'X71' <= substr(code, 1, 3) <= 'X83' /* definite self-harm */
      or 'Y21' <= substr(code, 1, 3) <= 'Y33' /* possible self-harm */
      or code = 'R45851' /* suicidal ideation, only R code we care about */
    ;
  run;

  proc sort data=cms&yy;
    by code desc;
  run;

  %head()
  %tail()
%mend;

%cmsicd10(16, 2016-Code-Descriptions-in-Tabular-Order.zip, icd10cm_codes_2016.txt)
%cmsicd10(17, 2017-ICD10-Code-Descriptions.zip, icd10cm_codes_2017.txt)
%cmsicd10(18, 2018-ICD-10-Code-Descriptions.zip, icd10cm_codes_2018.txt)

data comb10;
  merge cms16 cms17 cms18;
  by code desc;
  label code='ICD-10-CM code (no dot)'
    desc='Description (long, uppercase)'
  ;
  array cms {*} cms16-cms18;
  do i=1 to dim(cms);
    cms{i} = coalesce(cms{i}, 0);
  end;
  drop i;
  informat _all_;
run;

data flag10;
  set comb10;
  *----------------------------------------------------------------------------;
  * We already limited the CMS code lists to general areas of interest for     ;
  * general MHRN work. Now let's create flags for MHRN-specific Dx groups.     ;
  *----------------------------------------------------------------------------; 
  *----------------------------------------------------------------------------;
  * F01-F99 encompasses "Mental, Behavioral and Neurodevelopmental disorders," ;
  * only some of which are typically relevant to MHRN and/or SRS3 studies.     ;
  *----------------------------------------------------------------------------;
  length MEN DEM ALC DRU PSY SCH OPD AFF BIP DEP ANX PTS EAT PER GEN ASD PED ADD 
    CON REM 3
  ;
  label MEN='Mental disorder (1/0)'
    DEM='Dementia (1/0)'
    ALC='Alcohol use disorder (1/0)'
    DRU='Drug use disorder (1/0)'
    PSY='Psychotic disorder or symptoms (1/0)'
    SCH='Schizophrenia spectrum disorder (1/0)'
    OPD='Other (non-schizophrenic) psychotic disorder (1/0)'
    AFF='Affective/mood disorder (1/0)'
    BIP='Bipolar/manic disorder (1/0)'
    DEP='Depressive disorder or symptoms (1/0)'
    ANX='Anxiety/adjustment disorder, stress reaction, or anxiety symptoms (1/0)'
    PTS='Post-traumatic stress disorder (1/0)'
    EAT='Eating disorder (1/0)'
    PER='Personality disorder (1/0)'
    GEN='Gender identity disorder (1/0)'
    ASD='Autism spectrum disorder (1/0)'
    PED='Pediatric MH disorder (1/0)'
    ADD='Attention deficit disorder (1/0)'
    CON='Conduct disorder (1/0)'
    REM='Remission (1/0)'
  ;
  MEN = 0; DEM = 0; ALC = 0; DRU = 0; PSY = 0; SCH = 0; OPD = 0; AFF = 0;
  BIP = 0; DEP = 0; ANX = 0; PTS = 0; EAT = 0; PER = 0; GEN = 0; ASD = 0;
  PED = 0; ADD = 0; CON = 0; REM = 0;
  if code =: 'F' then do;
  *----------------------------------------------------------------------------;
  * Flag general MH universe (some of which gets overwritten in alcohol & drug ;
  * use section below).                                                        ;
  *----------------------------------------------------------------------------;
    MEN = 1;
    * Across disorders, flag codes that denote conditions in remission. *;
    if index(desc, 'REMISSION') > 0 then REM = 1;
    * Dementia *;
    if code in: ('F01', 'F02', 'F03') then DEM = 1;
    * Other mental disorders due to known physiological condition *;
      else if code in ('F060', 'F062') then PSY = 1;
      else if code =: 'F063' then do;
        AFF = 1;
        if code in: ('F0631', 'F0632') then DEP = 1;
          else if code =: 'F0633' then BIP = 1;
      end;
      else if code =: 'F064' then ANX = 1;
    * Alcohol & drug use (excluding tobacco dependence) *;
      else if code =: 'F1' then do;
        if code =: 'F10' and REM = 0 then ALC = 1;
          else if code ne: 'F17' and REM = 0 then DRU = 1; 
          else MEN = 0; * nicotine & remission not part of our MH "realm" *;
        if index(desc, 'PSYCHOTIC') > 0 then PSY = 1;
          else if index(desc, 'MOOD') > 0 then AFF = 1;
          else if index(desc, 'DEMENTIA') > 0 then DEM = 1;
          else if index(desc, 'ANXIETY') > 0 then ANX = 1;
      end;
    * Schizophrenia and other psychotic disorders *;
      else if code =: 'F2' then do;
        PSY = 1;
        if code in: ('F20', 'F21', 'F25') then do;
          SCH = 1;
          if code =: 'F250' then BIP = 1;
        end;
          else if code =: 'F2' then OPD = 1;
      end;      
    * Affective/mood disorders *;
    if code =: 'F3' then do;
      AFF = 1;
      * Bipolar disorder *;
      if code in: ('F30', 'F31') then BIP = 1;
      * Depression *;  
        else if code in: ('F32', 'F33') then DEP = 1;
        else if code = 'F340' then do; * Cyclothymic f.k.a. Affective PD *;
          BIP = 1;
          PER = 1;
        end;
        else if code = 'F341' then do; * Dysthymic f.k.a. Depressive PD *;
          DEP = 1;
          PER = 1;
        end;
    end;
    * Anxiety disorders (incl. stress reaction & adjustment) *;
      else if code in: ('F40', 'F41', 'F42', 'F43', 'F93.0') then do;
      * incl. childhood separation anxiety for ICD-10 continuity *;
        ANX = 1;
        if code =: 'F431' then PTS = 1;
          else if code in ('F4321', 'F4323') then DEP = 1;
      end;
    * Eating disorders (incl. childhood for ICD-9/-10 continuity) *;
      else if code in: ('F50', 'F982', 'F983') then EAT = 1;      
    * Puerperal psychosis --> include in depression *;                                      
      else if code = 'F53' then DEP = 1;
    * Personality disorders *;
      else if code =: 'F60' then do;
        PER = 1;
        if code = 'F601' then SCH = 1;
      end;
    * Gender identity disorders *;
      else if code =: 'F64' then GEN = 1;
    * ASD *;
      else if code =: 'F84' then ASD = 1;
    * Pediatric MH disorders *;
      else if code =: 'F9' then do;
        if code not in ('F984', 'F985', 'F99') then PED = 1;
    * ADD *;
        if code =: 'F90' then ADD = 1;
    * Conduct disorders *;
          else if code =: 'F91' then CON = 1;
          else if code = 'F930' then ANX = 1;
      end;
  end; 
  *----------------------------------------------------------------------------;
  * R00-R99 refers to "Symptoms, signs and abnormal clinical and laboratory    ;
  * findings, not elsewhere classified." The only one we need for MHRN/SRS3    ;
  * work is R45.851 "Suicidal ideations."                                      ;
  *----------------------------------------------------------------------------;
  length SUI 3;
  label SUI='Suicidal ideation (1/0)';
  SUI = 0;
  if code = 'R45851' then SUI = 1;
  *----------------------------------------------------------------------------;
  * Chapter-crossing concepts: Subsequent and sequela encounters, definite and ;
  * possible self-harm                                                         ;
  *----------------------------------------------------------------------------;
  length SUB SEQ DSH PSH 3;
  label SUB='Subsequent encounter (1/0)'
    SEQ='Sequela or late effects (1/0)'
    DSH='Definite self-harm (1/0)' 
    PSH='Possible self-harm (1/0)'
  ;
  SUB = 0; SEQ = 0; DSH = 0; PSH = 0;
  if index(desc, 'SUBSEQUENT') > 0 then SUB = 1;
  if index(desc, 'SEQUELA') > 0 then SEQ = 1;
  if 'X71' <= substr(code, 1, 3) <= 'X83'
    or (code =: 'T' and index(desc, 'INTENTIONAL SELF-HARM') > 0)
    or code = 'T1491' /* suicide attempt */
    then DSH = 1
  ;
    else if 'Y21' <= substr(code, 1, 3) <= 'Y33' 
      or (code =: 'T' and index(desc, 'UNDETERMINED') > 0)
      then PSH = 1
    ;
  *----------------------------------------------------------------------------;
  * S00-T88 refers to "Injury, poisoning and certain other consequences of     ;
  * external causes." Within this chapter we need to flag these MHRN/SRS3      ;
  * concepts:                                                                  ;
  * - Self-harm (see above)                                                    ;
  * - Wounds                                                                   ;
  * - Poisonings                                                               ;
  * - Traumatic brain injuries                                                 ;
  * - T8x Complications of surgical and medical care (SRS3 exclusions)         ;
  *----------------------------------------------------------------------------;
  length POI INJ WOU TBI 3;
  label POI='Poisoning (1/0)'
    INJ='Injury (1/0)'
    WOU='Wound-type injury (1/0)'
    TBI='Traumatic brain injury (1/0)'
  ;
  POI = 0; INJ = 0; WOU = 0; TBI = 0;
  if code in: ('S', 'T') then do;
    if index(desc, 'POISONING') > 0 or index(desc, 'TOXIC') > 0
      then POI = 1
    ;
      else do;
        INJ = 1;
        if index(desc, 'WOUND') > 0
          or index(desc, 'LACERATION') > 0
          or index(desc, 'TRAUMATIC AMPUTATION') > 0
          then WOU = 1
        ;
        if code in: ('S020', 'S021', 'S0281', 'S0291', 'S060', 'S061',
          'S063', 'S065', 'S066') then TBI = 1
        ;
      end;
  end;
run;  

*----------------------------------------------------------------------------;
* Check code ranges for SUB and SEQ codes.                                   ;
*----------------------------------------------------------------------------;
proc tabulate data=flag10;
  where sub = 1 or seq = 1;
  var sub seq;
  class code;
  format code $1.;
  table code='1st char ICD-10 code' all='Total'
    , sum='' * f=comma8. * (sub='SUB' seq='SEQ')
  ;
run;


*******************************************************************************;
* ICD-9                                                                       *;
*******************************************************************************;

*------------------------------------------------------------------------------;
* Read in all available ICD-9-CM code lists, compile, and deduplicate. This    ;
* will ensure that we have historical codes available for studies that cross   ;
* multiple years.                                                              ;
*------------------------------------------------------------------------------;

%let prefix9 = https://www.cms.gov/Medicare/Coding/ICD9ProviderDiagnosticCodes/Downloads;

%macro cmsicd9(yy, zipfile, zipmem);
  %dsdelete(cms&yy)

  %let ziploc = %sysfunc(getoption(work))\datafile.zip;

  filename download "&ziploc";

  proc http method='GET'
    out=download
    proxyhost="proxy.ghc.org"
    proxyport=8080
    url="&prefix9/&zipfile"
  ;
  run;

  filename inzip zip "&ziploc";

  data cms&yy;
    infile inzip("&zipmem") truncover;
    input @1 CODE $5. @7 DESC $24.;
    code = upcase(code);
    desc = upcase(desc);
    length CMS&yy 3;
    CMS&yy = 1;
    label CMS&yy="Code+desc in 20&yy CMS release (1/0)";
    if code in: ('29', '30', '31') /* mental health */
      or code in: ('8', '9') /* injury & poisoning */
      or code =: 'E95' /* definite self-harm */
      or code =: 'E98' /* possible self-harm */
      or code = 'V6284' /* suicidal ideation, only V code we care about */
    ;
  run;

  proc sort data=cms&yy;
    by code desc;
  run;

  %head()
  %tail()
%mend cmsicd9;

%cmsicd9(15, ICD-9-CM-v32-master-descriptions.zip, CMS32_DESC_SHORT_DX.txt)
%cmsicd9(14, cmsv31-master-descriptions.zip, CMS31_DESC_SHORT_DX.txt)
%cmsicd9(13, cmsv30_master_descriptions.zip, CMS30_DESC_SHORT_DX.txt)
%cmsicd9(12, cmsv29_master_descriptions.zip, CMS29_DESC_SHORT_DX.txt)
%cmsicd9(11, cmsv28_master_descriptions.zip, CMS28_DESC_SHORT_DX.txt)
%cmsicd9(10, v27_icd9.zip, CMS27_DESC_SHORT_DX.txt)
%cmsicd9(09, v26_icd9.zip, V26 I-9 Diagnosis.txt)
%cmsicd9(08, v25_icd9.zip, I9diagnosesV25.txt)
%cmsicd9(07, v24_icd9.zip, I9diagnosis.txt)
%cmsicd9(06, v23_icd9.zip, I9DX_DESC.txt)

data comb09;
  merge cms06 cms07 cms08 cms09 cms10 cms11 cms12 cms13 cms14 cms15;
  by code desc;
  label code='ICD-9-CM code (no dot)'
    desc='Description (short, uppercase)'
  ;
  array cms {*} cms06-cms15;
  do i=1 to dim(cms);
    cms{i} = coalesce(cms{i}, 0);
  end;
  drop i;
  informat _all_;
run;

proc sort data=comb09 nodup;
  by code desc;
run;

proc sort data=comb09 nodupkey;
  by code desc;
run;

data flag09;
  set comb09;
  *----------------------------------------------------------------------------;
  * We already limited the CMS code lists to general areas of interest for     ;
  * general MHRN work. Now let's create flags for MHRN-specific Dx groups.     ;
  *----------------------------------------------------------------------------; 
  *----------------------------------------------------------------------------;
  * 290-319 encompasses "Mental disorders," only some of which are typically   ;
  * relevant to MHRN and/or SRS3 studies.                                      ;
  *----------------------------------------------------------------------------;
  length MEN DEM ALC DRU PSY SCH OPD AFF BIP DEP ANX PTS EAT PER GEN ASD PED ADD 
    CON REM 3
  ;
  label MEN='Mental disorder (1/0)'
    DEM='Dementia (1/0)'
    ALC='Alcohol use disorder (1/0)'
    DRU='Drug use disorder (1/0)'
    PSY='Psychotic disorder or symptoms (1/0)'
    SCH='Schizophrenia spectrum disorder (1/0)'
    OPD='Other (non-schizophrenic) psychotic disorder (1/0)'
    AFF='Affective/mood disorder (1/0)'
    BIP='Bipolar/manic disorder (1/0)'
    DEP='Depressive disorder or symptoms (1/0)'
    ANX='Anxiety/adjustment disorder, stress reaction, or anxiety symptoms (1/0)'
    PTS='Post-traumatic stress disorder (1/0)'
    EAT='Eating disorder (1/0)'
    PER='Personality disorder (1/0)'
    GEN='Gender identity disorder (1/0)'
    ASD='Autism spectrum disorder (1/0)'
    PED='Pediatric MH disorder (1/0)'
    ADD='Attention deficit disorder (1/0)'
    CON='Conduct disorder (1/0)'
    REM='Remission (1/0)'
  ;
  MEN = 0; DEM = 0; ALC = 0; DRU = 0; PSY = 0; SCH = 0; OPD = 0; AFF = 0;
  BIP = 0; DEP = 0; ANX = 0; PTS = 0; EAT = 0; PER = 0; GEN = 0; ASD = 0;
  PED = 0; ADD = 0; CON = 0; REM = 0;
  if code in: ('29', '30', '31') then do;
  *----------------------------------------------------------------------------;
  * Flag general MH universe (some of which gets overwritten in alcohol & drug ;
  * use section below).                                                        ;
  *----------------------------------------------------------------------------;
    MEN = 1;
    * Across disorders, flag codes that indicate remission. *;
    if index(desc, ' REM') > 0 or index(desc, '-REM') then REM = 1;
    * Dementia *;
    if code in: ('290', '2941', '2942') then DEM = 1;
    * Other mental disorders due to known physiological condition *;
      else if code in ('29381', '29382') then PSY = 1;
      else if code = '29383' then AFF = 1;
      else if code = '29384' then ANX = 1;
    * Alcohol- & drug-induced mental disorders *;
      else if code =: '291' then do;
        ALC = 1;
        if code = '2912' then DEM = 1;
          else if code in ('2913', '2915') then PSY = 1;
      end;
      else if code =: '292' then do;
        DRU = 1;
        if code in ('29211', '29212') then PSY = 1;
          else if code = '29282' then DEM = 1;
          else if code = '29284' then AFF = 1;
      end;
    * Schizophrenia, episodic mood, and other psychotic disorders *;
      else if code =: '295' then do;
        PSY = 1;
        SCH = 1;
      end;
      else if code =: '296' then do;
        AFF = 1;
        if code in: ('2962', '2963', '29682') then DEP = 1;
          else if code ne: '2969' then BIP = 1;
      end;
      else if code in: ('297', '298') then do;
        PSY = 1;
        OPD = 1;
        if code = '2980' then DEP = 1;
      end;     
    * ASD *;
      else if code =: '299' then ASD = 1;
    * Anxiety disorders *;
      else if code in: ('3000', '3002', '3003') then ANX = 1;
    * Dysthymic disorder *;
      else if code = '3004' then do;
        DEP = 1;
        PER = 1;
      end;
    * Personality disorders *;
      else if code =: '301' then do;
        PER = 1;
        if code = '30110' then BIP = 1;
          else if code in ('30112', '30113') then DEP = 1;
        * N.B. Chronic hypomanic & Chronic depressive --> Other PD in ICD-10 *;
          else if code in ('30120', '30122') then SCH = 1;
      end;
    * Gender identity disorders *;
      else if code in ('3025', '3026', '30285') then GEN = 1;
    * Alcohol & drug dependence *;
      else if code =: '303' then ALC = 1;
      else if code =: '304' then DRU = 1;
    * Alcohol & drug abuse (excl. tobacco) *;
      else if code =: '305' then do;
        if code =: '3050' and REM = 0 then ALC = 1;
          else if code ne: '3051' and REM = 0 then DRU = 1;
          else MEN = 0; * nicotine & remission not part of our MH "realm" *;        
      end;
    * Eating disorders *;
      else if code in: ('3071', '3075') then EAT = 1;
    * Acute reaction to stress *;
      else if code =: '308' then ANX = 1;
    * Adjustment reaction *;
      else if code in ('3090', '3091') then DEP = 1;
      else if code in ('30921', '30924') then ANX = 1;
      else if code = '30928' then do;
        ANX = 1;
        DEP = 1;
      end;
      else if code = '30981' then do;
        ANX = 1;
        PTS = 1;
      end;
    * Mild depression *;
      else if code = '311' then DEP = 1;
    * Conduct disorders *;
      else if code =: '312' and code ne: '3123' then do;
        CON = 1;
        PED = 1;
      end;
      else if code = '31381' then do;
        CON = 1;
        PED = 1;
      end;
    * ADD *;
      else if code =: '314' then do;
        ADD = 1;
        PED = 1;
        if code = '3142' then CON = 1;
      end;
    * Flag additional pediatric MH disorders not already labeled above *;
    if code in: ('30921', '30922', '30923', '313') then PED = 1;  
  end; 
  *----------------------------------------------------------------------------;
  * V01-V91 refers to "Supplementary classification of factors influencing     ;
  * health status and contact with health services." The only one we need for  ;
  * MHRN/SRS3 work is V62.84 Suicidal ideation.                                ;
  *----------------------------------------------------------------------------;
  length SUI 3;
  label SUI='Suicidal ideation (1/0)';
  SUI = 0;
  if code = 'V6284' then SUI = 1;
  *----------------------------------------------------------------------------;
  * Chapter-crossing concepts: Definite and possible self-harm, late effects   ;
  * (a.k.a. sequela in ICD-10 parlance)                                        ;
  *----------------------------------------------------------------------------;
  length DSH PSH SEQ 3;
  label DSH='Definite self-harm (1/0)'
    PSH='Possible self-harm (1/0)'
    SEQ='Sequela or late effects (1/0)'
  ;
  DSH = 0; PSH = 0; SEQ = 0;
  if code =: 'E95' then do;
    DSH = 1;
    if code = 'E959' then SEQ = 1;
  end;
    else if code =: 'E98' then do;
      PSH = 1;
      if code = 'E989' then SEQ = 1;
    end;
  *----------------------------------------------------------------------------;
  * 800-999 refers to "Injury and poisoning." Within this chapter we need to   ;
  * flag these MHRN/SRS3 concepts:                                             ;
  * - Self-harm (see above)                                                    ;
  * - Late effects, a.k.a. sequela (SRS3 exclusions)                           ;
  * - Subsequent encounters (ICD-10 concept, all ICD-9 codes will have SUB=0)  ;
  * - Wounds                                                                   ;
  * - Poisonings                                                               ;
  * - Traumatic brain injuries                                                 ;
  * - Complications of surgical and medical care, NEC (SRS3 exclusions)        ;
  *----------------------------------------------------------------------------;
  length POI INJ WOU TBI SUB 3;
  label POI='Poisoning (1/0)'
    INJ='Injury (1/0)'
    WOU='Wound-type injury (1/0)'
    TBI='Traumatic brain injury (1/0)'
    SUB='Subsequent encounter (1/0)'
  ;
  POI = 0; INJ = 0; WOU = 0; TBI = 0; SUB = 0;
  if code in: ('8', '9') then do;
    if '905' <= substr(code, 1, 3) <= '909' then SEQ = 1;
    else if '960' <= substr(code, 1, 3) <= '989' then POI = 1;
    else do;
      INJ = 1;
      if '905' <= substr(code, 1, 3) <= '909' then SEQ = 1;
      if '870' <= substr(code, 1, 3) <= '897' then WOU = 1;
      if '800' <= substr(code, 1, 3) <= '804'
        or '850' <= substr(code, 1, 3) <= '854'
        then TBI = 1
      ;
    end;
  end;
run;  

*******************************************************************************;
* Combine ICD-10 and ICD-9 lists and output to Excel for PI review.           *;
*******************************************************************************;
libname out "&root";

%dsdelete(out.&fn._20180531|legend)

data out.&fn._20180531 (label="Created by &fn._20180531.sas");
  retain REV CODE DESC MEN DEM ALC DRU PSY SCH OPD AFF BIP DEP ANX PTS EAT PER
    GEN ASD PED ADD CON REM MULTI UNCAT SUI DSH PSH POI INJ WOU TBI SUB SEQ
    CMS06-CMS18 
  ;
  length REV 3;
  label REV='ICD-?-CM Revision (9/10)';
  set flag10 (in=a) flag09;
  if a then REV = 10;
    else REV = 9;
  array cms {*} cms06-cms18;
  do i=1 to dim(cms);
    cms{i} = coalesce(cms{i}, 0);
  end;
  drop i;
  label CODE='Code (no dot)' DESC='Description (ICD-10: Long, ICD-9: Short)';
  length MULTI UNCAT 3;
  label MULTI='MH code appears in multiple standard MHRN subcategories (1/0)'
    UNCAT='MH code not assigned to any standard MHRN subcategories (1/0)'
  ;
  if MEN = 1 
    and sum(DEM, ALC, DRU, SCH, OPD, BIP, DEP, ANX, PTS, EAT, PER, ASD, ADD, CON) > 1
    then MULTI = 1
  ;
    else MULTI = 0;
  if MEN = 1
    and sum(DEM, ALC, DRU, SCH, OPD, BIP, DEP, ANX, PTS, EAT, PER, ASD, ADD, CON) = 0
    then UNCAT = 1
  ;
    else UNCAT = 0;
run;

proc contents data=out.&fn._20180531 noprint out=legend (keep=varnum name label);
run;

proc sort data=legend (rename=(name=VARNAME));
  by varnum;
run;

proc export data=legend (drop=varnum) dbms=excel outfile="&root\&fn..xlsx"
  replace
;
  sheet="LEGEND";
run;

proc export data=out.&fn._20180531 dbms=excel outfile="&root\&fn..xlsx" replace;
  sheet="CODES";
run;

*******************************************************************************;
* 20181204 CORRECTIONS                                                        *;
*******************************************************************************;
data out.srs3_dx_codes_20181204 (label="V20181204 corrects V20180531 to set
 MEN=ALC=DRU=0 for alc/drug dep in remiss. N.B. Primary key is CODE+DESC. Some
 codes appear more than once because their descriptions changed over ICD 
 versions.")
;
  set out.srs3_dx_codes_20180531;
  *----------------------------------------------------------------------------;
  * Correct issue in which alcohol/drug dependence in remission had been       ;
  * included in MHRN 'realm' (MEN=1) as well as ALC/DRU subcategories.         ;
  *----------------------------------------------------------------------------;
  if code =: '303' and rem = 1 then do;
    MEN = 0;
    ALC = 0;
  end;
    else if code =: '304' and rem = 1 then do;
      MEN = 0;
      DRU = 0;
    end;
  *----------------------------------------------------------------------------;
  * Recalculate MULTI and UNCAT variables to reflect corrections above.        ;
  *----------------------------------------------------------------------------;
  if MEN = 1 
    and sum(DEM, ALC, DRU, SCH, OPD, BIP, DEP, ANX, PTS, EAT, PER, ASD, ADD, CON) > 1
    then MULTI = 1
  ;
    else MULTI = 0;
  if MEN = 1
    and sum(DEM, ALC, DRU, SCH, OPD, BIP, DEP, ANX, PTS, EAT, PER, ASD, ADD, CON) = 0
    then UNCAT = 1
  ;
    else UNCAT = 0;
  *----------------------------------------------------------------------------;
  * Relabel MEN to reflect what it actually means in MHRN context.             ;
  *----------------------------------------------------------------------------;
  label MEN='Mental disorder typically included in MHRN analyses (1/0)';
run;

options ps=54 ls=90;
proc compare base=out.&fn._20180531 compare=out.&fn._20181204;
run;

proc contents data=out.&fn._20181204 noprint out=legend (keep=varnum name label);
run;

proc sort data=legend (rename=(name=VARNAME));
  by varnum;
run;

proc export data=legend (drop=varnum) dbms=excel 
  outfile="&root\&fn._20181204.xlsx" replace
;
  sheet="LEGEND";
run;

proc export data=out.&fn._20181204 dbms=excel 
  outfile="&root\&fn._20181204.xlsx" replace
;
  sheet="CODES";
run;

*******************************************************************************;
* END OF PROGRAM                                                              *;
*******************************************************************************;
