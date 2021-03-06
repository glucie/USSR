/**
*
*	Macro qui r�gionalise les donn�es en fonction des valeurs de clap<br/>
*		elle calcule un ratio dom/france pour chaque siren dont un etab est present dans le dom<br/>
*		par d�faut ce ratio vaut : taux=masse salariale dom / masse salariale  france entiere, mais il y a des cas particuliers<br/>
*<br/>				cas 1		:	pas de redressement ; ie toutes les donnees sont presentes => on applique ce taux calcul� 
*<br/>		S'IL MANQUE DES DONNEES DE REMUNERATION DES ETABS
*<br/>				cas 10		:	taux=1 car il s'agit d'une entreprise individuelle, si plusieurs etab => taux = nbEtabDom/nbEtabTotal
*<br/>				cas 11		:	taux=1 car le siege est en DFA, si plusieurs etab => taux = nbEtabDom/nbEtabTotal
*<br/>				cas 12		:	taux=1 car absent du fichier clap (sera mis a  12 par un process ulterieur mais est stock� dej dans le format
*<br/>		S'IL MANQUE DES DONNEES DE REMUNERATION DE L'ENTREP
*<br/>				cas 20		: 	taux=0 car rem(entrep)=0
*<br/>				cas 30		:	taux comme si la remun du dep = max des autres dep, proportionnellement au nombre etab/entrep (cas ou il manque des remun sur un DFA)
*<br/>				cas 31		: 	taux corrig� car reventill� sur les autres DFA (1 cas 30 sur les  3 DFAs)
*<br/>				cas 40		: 	taux fix� par fichier externe xls
*
*		<p>la macro s'utilise comme une proc�dure exemple : </p>
*			<ul><li>%regio_clap(libsrc=clap,tabent=entrep,tabetab=etab,fichierxls=c:\mes documents\clap.xls,libcible=work,tabcible=resultat);</li>
*				Va construire la table work.resultat qui contient pour chaque entreprise son "taux de r�gionalisation" par DFA, <br/>
*				calcul� a partir des masses salariales des tables clap.entrep et clap.etab, le tout forc� par le fichier clap.xls
*			</ul>
*
*	@param	libsrc		libname ou se trouve les tables clap
*	@param	tabent		nom de la table qui contient les donn�es entreprises
*	@param	tabetab		nom de la table qui contient les donn�es �tablissements
*	@param	libcible	libname de la table ou stocker la table de r�gionalisation
*	@param	tabcible	nom de la table de r�gionalisation
*	@param	fichierxls	chemin complet du fichier xls comprenant la feuille "regio" fixant une r�partition pour un siren (si vide - par defaut- pas de forcage)
*	
*
*	@return 	la table libcible.tabcible qui contient pour chaque sirenXcodep un ratio de repartitions des valeurs d'int�rets
*
*
*/
%macro regio_clap(libsrc=,tabent=,tabetab=,fichierxls=,libcible=,tabcible=);
	/*filtrer les donn�es clap, uniquement les colonnes necessaires et les mettre dans la work pour un travail plus efficace*/
	data clap_ent;
		set &libsrc..&tabent.;
		keep siren nomen dcsiege apen rembrute cj;
	run;
	data clap_etab;
		set &libsrc..&tabetab.(where=(substr(dc,1,3) ne '974')); /*on ne garde pas la reunion*/
		codep=substr(dc,1,3);
	run;
	/*agreger les donnees etab par siren et deapartement*/
	proc means data=clap_etab noprint sum;
		class siren codep;
		ways 2;
		var rembrute;
		output out=ent_dep(drop=_type_ _freq_)  sum(rembrute)=remb_ent_dep N=nb_etab;
	run;
	proc means data=ent_dep noprint sum;
		class siren;
		ways 1;
		var nb_etab remb_ent_dep;
		output out=ent_dep_tot(drop=_type_ _freq_)  sum(nb_etab)=nb_tot max(nb_etab)=nb_max max(remb_ent_dep)=rem_max;
	run;
	/* pour chaque croisement sirenXdepartement, calcul du taux rembrute departement / rembrute totale */
	proc sql;
		create table clap_taux as
			select a.*, b.* from ent_dep as a left outer join ent_dep_tot as b on (a.siren=b.siren)
		;
		create table clap_regio as
			select 
				a.*,b.*,remb_ent_dep/rembrute as Part_Masse_Salariale 
			from 
				clap_ent as a 
				inner join clap_taux as b on (a.siren=b.siren)
		;
	quit;
	proc format ;
		value redressement
			0 	=	"Pas de redressement"
			10 	=	"1 car entreprise individuelle, proportionnellement au nombre etab/entrep"
			11	=	"1 car siege en DFA, proportionnellement au nombre etab/entrep"
			12	=	"1 car absent clap"
			20	=	"0 car rem(entrep) = 0"
			30	=	"max, proportionnellement au nombre etab/entrep"
			31	=	"reventill� sur les dfa presents"
			40	=	"forc� manuellement"
		;
	run;
	/* redressement de ce taux en fonction des differents cas */
	data clap_regio;
		set clap_regio;
		format redressement redressement.;
		label redressement="Redressement du taux de masse salariale";
		redressement=0;
		siegeDfa=0;/* determine si le siege de l'entreprise est dans un dfa 0=non, 1=oui*/
		if substr(dcsiege,1,3) in ('971','972','973') then siegeDfa=1;
		if Part_Masse_Salariale=. then do;
			if substr(cj,1,1) in ('1','2') then do;/*cj commence par 1 ou 2 => entrepreneur individuel*/
				Part_Masse_Salariale= nb_etab/nb_tot;
				redressement=10;
			end;
			else do;
				if siegeDfa=1 then do;
					Part_Masse_Salariale= nb_etab/nb_tot;
					redressement=11;						
				end;
				else do;
					Part_Masse_Salariale= 0;
					redressement=20;
				end;
			end;
		end;
		if Part_Masse_Salariale=0 then do;
			if rem_max ne 0 then do;
				Part_Masse_Salariale=rem_max/rembrute*nb_etab/nb_max;
				redressement=30;
			end;
		end;
	run;
	/*calage des redressements sur la somme des part_masse_salariales non redressees, pour ne pas sur estimer les variables d'interets*/	
	proc sql;
		create table part_mass_sal_non_red as
			select siren, sum(part_masse_salariale) as somme_part_nored from clap_regio where redressement < 20 group by siren
		;
		create table part_mass_sal_totale as
			select siren, sum(part_masse_salariale) as somme_part_tot from clap_regio group by siren
		;
		create table clap_regio_redresse as
			select 
				a.*
				, case when b.somme_part_nored=. then 0 else b.somme_part_nored end as part_nored
				, case when c.somme_part_tot=0 then 1 else c.somme_part_tot end as part_tot
				, part_masse_salariale * (case when b.somme_part_nored=. then 0 else b.somme_part_nored end) / (case when c.somme_part_tot=0 then 1 else c.somme_part_tot end) as part_masse_salariale_redressee
				/* part masse salariale redresse  = part_masse_salariale * part_nored /part_totale => part_totale = cste */
			from
				clap_regio as a 
				left outer join part_mass_sal_non_red as b on a.siren=b.siren
				left outer join part_mass_sal_totale as c on a.siren=c.siren
		;
	quit;
	/*integration des forcages manuels de regionalisation*/
	%if &fichierxls ne %then %do;
		PROC IMPORT OUT= regio_manuel 
		            DATAFILE= "&fichierxls" 
		            DBMS=EXCELCS REPLACE;
		     SHEET="regio"; 
		     SCANTEXT=YES;
		     USEDATE=YES;
		     SCANTIME=YES;
		RUN;
		data regio_manuel;
			set regio_manuel;
			if siren ne '012345678';
		run;
		proc sql;
			create table clap_force as 
				select a.*, b.part, b.siren as new_siren, b.codep as new_codep, b.dcsiege as new_dcsiege from clap_regio_redresse as a full outer join regio_manuel as b on (a.siren=b.siren and a.codep=b.codep)
			;		
		quit;
		data clap_regio_force(drop=part new_siren new_codep new_dcsiege);
			set clap_force;
			if part ne . then do; /*si la part est forc�e, on la prend en compte et on mets le mode de redressement a 40 (force manuellement)*/
				part_masse_salariale_redressee=part;
				siren=new_siren;
				codep=new_codep;
				redressement=40;
				dcsiege=new_dcsiege;
			end;
		run;
	%end;
	%else %do; /* si pas de frocage manuel, on remplace par la table initiale */
		data clap_regio_force;
			set clap_regio_redresse;
		run;
	%end;
	/* ultime redressement : si le redressement sur un autre d�partement a fait modifi� le taux initial non redresse de plus de 1e-5 
					=> il a ete reventill� 
					=> redressement = 31
		ajout de la variable permettant de distinguer les entreprises locales (S111) des entreprises non r�gionales (S112)
					=> entrep_loc = 1 si codep=dcsiege, 0 sinon
	*/
	data &libcible..&tabcible.;
		set clap_regio_force;
		entrep_loc=0;
		if codep=substr(dcsiege,1,3) then entrep_loc=1;
		if redressement=0 and abs(part_masse_salariale - part_masse_salariale_redressee)>1E-5 then redressement=31;
	run;
%mend;
