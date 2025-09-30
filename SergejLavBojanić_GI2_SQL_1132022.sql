



create or replace function my_verizioniranjeINSPIRE() returns trigger as
$$
declare
crs1 CURSOR FOR SELECT * FROM public.osnovnajedinicavlasnistva;
crs2 CURSOR FOR SELECT *  FROM public.cadastralzone;
r1 record;
r2 record;
begin
	OPEN crs1;
	OPEN crs2;
FETCH first FROM crs1 INTO r1;
FETCH first FROM crs2 INTO r2;

-- nakon brisanja parcele koja pripada  jednici
--menjam verziju toj admin. jedinici, jedinici vlanistva
IF r1 is not null THEN UPDATE cadastralzone SET cadastralzone."version" = cadastralzone."version"+1 WHERE ST_Contains(cadastralzone."geometry",OLD."geometry") and
cadastralzone."level"=1;--nije reformiran poligon jer mi razdvojene klase 
END IF;

--omogucuju razdvojene slojeve i time nepreklapanje
IF r2 is not null THEN UPDATE OsnovnaJedinicaVlasnistva SET OsnovnaJedinicaVlasnistva."version"=OsnovnaJedinicaVlasnistva."version"+1 FROM katastarskaparcela WHERE 
OsnovnaJedinicaVlasnistva."id"=katastarskaparcela."fk_ovj";
END IF;

	CLOSE crs1;
	CLOSE crs2;
return OLD;
end;
$$
language plpgsql;

CREATE or replace TRIGGER ad_INSPIRE_CadastralZonelVersion
AFTER DELETE ON public.katastarskaparcela
FOR EACH ROW EXECUTE FUNCTION my_verizioniranjeINSPIRE();-- kljucno je da bude za svaki zapis, ne operaciju

CREATE or replace TRIGGER ad_INSPIRE_OVJVersion
AFTER DELETE ON public.katastarskaparcela
FOR EACH ROW EXECUTE FUNCTION my_verizioniranjeINSPIRE();-- kljucno je da bude za svaki zapis, ne operaciju

CREATE or replace FUNCTION my_povrsina_cz() returns trigger as
$$
begin

IF ST_NRings(NEW."geometry")=2 THEN 
NEW."povrsina":= ST_Area(concat('POLYGON(',concat(substr(ST_AsText(ST_ExteriorRing(NEW."geometry")),11),')')));
ELSE NEW."povrsina":=ST_Area(NEW."geometry");
END IF;
return NEW;
end;
$$
language plpgsql;

CREATE or replace FUNCTION my_povrsina_cp() returns trigger as
$$
declare
base decimal(36,2);
begin

IF ST_NRings(new."geometry")>1 THEN 
base = ST_Area(concat('POLYGON(',concat(substr(ST_AsText(ST_ExteriorRing(NEW."geometry")),11),')')));

		FOR i IN 1..ST_NRings(new."geometry")-1 
			LOOP
			base = base-ST_Area(concat('POLYGON(',concat(substr(ST_AsText(ST_InteriorRingN(NEW."geometry",i)),11),')'))); 
			END LOOp;
NEW."povrsina" = base;
ELSE NEW."povrsina" = ST_Area(NEW."geometry");
END IF;

return NEW;
end;
$$
language plpgsql;

CREATE or replace TRIGGER bi_povrsina_CZ BEFORE INSERT ON public.cadastralzone FOR EACH ROW EXECUTE FUNCTION my_povrsina_cz();
CREATE or replace TRIGGER bi_povrsina_CP BEFORE INSERT ON public.katastarskaparcela FOR EACH ROW EXECUTE FUNCTION my_povrsina_cp();
CREATE or replace TRIGGER bu_povrsina_CP BEFORE UPDATE ON public.katastarskaparcela FOR EACH ROW EXECUTE FUNCTION my_povrsina_cp();





create or replace function parcelaPreklapaNekuDruguParcelu() returns void as
$$
declare 

begin

perform setval('"katastarskaparcela_extId_kp_seq"'::regclass,currval('"katastarskaparcela_extId_kp_seq"'::regclass),false);
raise exception 'Parcela preklapa neku drugu parcelu!';


end;
$$
language plpgsql;

CREATE or replace FUNCTION my_topoParcela() returns trigger as
$$
declare 
c5 CURSOR (geom geometry('POLYGON',3908)) FOR SELECT * FROM  public.katastarskaparcela WHERE ST_Overlaps(geom,katastarskaparcela."geometry");
r record;
begin
OPEN c5(NEW."geometry");
FETCH FIRST FROM c5 INTO r;
IF FOUND THEN PERFORM parcelaPreklapaNekuDruguParcelu(); -- ponasa se kao da nije ni dodeljen, tj. is_called = false
END IF;
CLOSE c5;
return new;
end;
$$
language plpgsql;


CREATE or replace TRIGGER bi_topoParcelaTrigger
BEFORE INSERT ON public.katastarskaparcela
FOR EACH ROW EXECUTE FUNCTION  my_topoParcela();

CREATE or replace FUNCTION my_zoniranje(geom geometry("POLYGON",3908), visiNivo integer) returns bigint as 
$$

begin
return "Id_cz" from CadastralZone where ST_Within(geom,CadastralZone."geometry") and CadastralZone.level=visiNivo;
-- nije reformiran poligon jer mi razdvojene klase omogucuju razdvojene slojeve i time nepreklapanje
end;
$$
language plpgsql;

CREATE or replace FUNCTION my_setDefaultZoneForCadastralParcel() returns TRIGGER as 
$$
begin

NEW."fk_cz" :=  my_zoniranje(NEW.geometry,1);
return NEW;--zapis koji je insertovan pa izmenjen ovom metodom
--sada mozes da cinis tablicu KatastarskaParcela, NEW! 
return NEW;
end;
$$
language plpgsql;

CREATE or replace TRIGGER bi_setDefaultZoneForCadastralParcelTrigger 
BEFORE INSERT ON public.KatastarskaParcela
FOR EACH ROW EXECUTE FUNCTION my_setDefaultZoneForCadastralParcel();

CREATE or replace FUNCTION my_upperZoneId(myLevel integer, geom geometry("MULTIPOLYGON",3908)) returns bigint as
$$

begin

return "Id_cz" from public.CadastralZone where CadastralZone."level" = myLevel+1 and 
ST_Within(ST_AsText(geom),concat('POLYGON(',concat(substr(ST_AsText(ST_InteriorRingN(CadastralZone."geometry",1)),11),')')));
end;
$$
language plpgsql;

CREATE or replace FUNCTION my_lowerZoneId(myLevel integer, geom geometry("MULTIPOLYGON",3908)) returns  TABLE( "Idx" bigint) as
$$
begin
if ST_NRings(geom)=2 then return query select"Id_cz" from public.CadastralZone where CadastralZone."level" = myLevel-1 and ST_Within(ST_AsText(CadastralZone."geometry"),concat('POLYGON(',concat(substr(ST_AsText(ST_InteriorRingN(geom,1)),11),')')));
end if;-- ovaj if je zbog k.o. koje nemaju ring
end;
$$
language plpgsql;

create or replace function my_hirearhijaJedinicaNijeDobra() returns void as
$$



begin





perform setval('"cadastralzone_Id_cz_seq"'::regclass,currval('"cadastralzone_Id_cz_seq"'::regclass),false);
raise exception 'Hirerarhija jedinica nije topoloski dobra!';


end;
$$
language plpgsql;




create or replace function my_jediniceSePreklapaju() returns void as
$$

begin


perform setval('"cadastralzone_Id_cz_seq"'::regclass,currval('"cadastralzone_Id_cz_seq"'::regclass),false);
raise exception 'Jedinice se preklapaju!';


end;
$$
language plpgsql;




CREATE or replace FUNCTION my_adjustNewCadastralZone() returns TRIGGER as
$$
declare 
c4 CURSOR (mojaKlasa bigint) FOR SELECT * FROM public.cadastralzone WHERE  public.cadastralzone."jedinicaVisegNivoa"=mojaKlasa;
r record;
begin

if  my_upperZoneId(NEW."level",NEW."geometry") is null and not NEW."level"=3 then PERFORM my_hirearhijaJedinicaNijeDobra();
--ovo znaci da se sekvenca ponasa kao da nije ni dodelila new."Id_cz"
else NEW."jedinicaVisegNivoa" = my_upperZoneId(NEW."level",NEW."geometry");
end if;

OPEN c4(new."jedinicaVisegNivoa");
	FETCH FIRST FROM c4 INTO r;
while FOUND 
							loop
IF st_overlaps(new."geometry", r."geometry") THEN PERFORM my_jediniceSePreklapaju();
END IF;
	FETCH NEXT FROM c4 INTO r;
		                 end loop;


CLOSE c4;
return NEW;
end;
$$
language plpgsql;


CREATE or replace TRIGGER bi_adjustNewCadastralZoneTrigger
BEFORE INSERT ON CadastralZone
FOR EACH ROW EXECUTE FUNCTION my_adjustNewCadastralZone();

CREATE or replace FUNCTION my_adjustUpdatedCadastralZone() returns TRIGGER as
$$
begin
NEW."jedinicaVisegNivoa" =  my_upperZoneId(NEW."level",NEW."geometry");
return NEW;
end;
$$
language plpgsql;

CREATE or replace TRIGGER ai_adjustNewCadastralZoneTrigger-- ovo je neophodno pri normalizaciji indekasa, da bih pored prosljedivanja levelu nize i sama sebi dodelila novi preneseni kljuc
AFTER UPDATE ON CadastralZone-- u suprotnom greska se manifestuje kao situaciju u kojoj najvisi level u novoj hirearhiji nakon brisana prethodne najvise, ima vrednost kolone JedinicaVisegNivoa kao st je imao pre brisanja jedinice iznad, odnosno jednak idx te brisane jedinice 
FOR EACH ROW EXECUTE FUNCTION my_adjustUpdatedCadastralZone();


CREATE or replace FUNCTION my_updateLoewrLevelCadastralParcel() returns TRIGGER as
$$

begin

UPDATE cadastralzone
SET "jedinicaVisegNivoa" = new."Id_cz"
where "Id_cz" in (select my_lowerZoneId(new."level", new."geometry"));
return new;
end;
$$

language plpgsql;



CREATE or replace TRIGGER ai_updateLowerLevelCadastralParcelTrigger-- zeznuo, trbalo je ici LevelZone, ne LevelCadastralParcel
after INSERT ON CadastralZone -- za isti zapis koji je prethodno INSERTOVAN , sihrono
FOR EACH ROW EXECUTE procedure  my_updateLoewrLevelCadastralParcel();

--ovbjasnjenje sledecg triggera se nalazi u slicnom bloku triggera koji se odnosi na parcele
CREATE or replace TRIGGER au_updateLowerLevelCadastralParcelTrigger
AFTER UPDATE ON CadastralZone  -- ukratko, UPDATE ce biti samo za indeks od strane triggera normalize
FOR EACH ROW EXECUTE FUNCTION  my_updateLoewrLevelCadastralParcel();


CREATE or replace FUNCTION my_updateCadastralParcelToNewZone() returns TRIGGER as
$$
begin
UPDATE KatastarskaParcela SET "fk_cz" = NEW."Id_cz" where ST_Within(KatastarskaParcela."geometry",NEW."geometry") and NEW."level"=1; -- jedinica viseg niva koja je verovatno izgubljena pri brisanju radi kriranja nove
return NEW;-- imao sam katastrofalni previd, propust, nisam vidio da ako ne stavim dodatni uslov NEW."Id_cz"=1 moze se desiti da se i pri novoj politickoj opstini dodanoj u zone updatue parcela!
end;
$$
language plpgsql;


CREATE or replace TRIGGER ai_updateCadastralParcelToNewZoneTrigger
AFTER INSERT ON CadastralZone -- za isti zapis koji je prethodno INSERTOVAN , sihrono
FOR EACH ROW EXECUTE procedure my_updateCadastralParcelToNewZone();
-- medjutim, parcele treba azurirati i pri projeni zone pod kojom se nalaze, tj normalizaciji idx-a
CREATE or replace TRIGGER au_updateCadastralParcelToNewZoneTrigger
AFTER UPDATE ON CadastralZone -- opet after da bi sve bilo sihrono, a NEW u trigger funkciji je update-ovana zona, slicno kao prethodno novododa
FOR EACH ROW EXECUTE FUNCTION my_updateCadastralParcelToNewZone();



create or replace function my_normalizeIfEmpty() returns trigger as
$$
DECLARE
r record;
c CURSOR FOR SELECT * FROM public.cadastralzone;
begin
OPEN c;
FETCH FIRST FROM c INTO r;

IF not FOUND THEN ALTER SEQUENCE "cadastralzone_Id_cz_seq" RESTART WITH 1;
end if;
close c;
return old;
end;
$$
language plpgsql;

create or replace TRIGGER ad_normalizeIfEemptyTrigger
after delete on cadastralzone
for each statement  execute function my_normalizeIfEmpty();

create or replace function my_sortiraj(i bigint) returns void as
$$
declare
c2 CURSOR (x bigint) FOR SELECT * FROM public.cadastralzone WHERE public.cadastralzone."Id_cz">x ;
r4 public.cadastralzone%rowtype;
idx bigint :=i;
begin
OPEN c2(idx);



FETCH FIRST FROM c2 INTO r4;

while FOUND  
			loop 
UPDATE public.cadastralzone SET "Id_cz"=idx WHERE CURRENT OF c2;
 idx:=idx+1;
 FETCH NEXT FROM c2 INTO r4;
			end loop;
			
EXECUTE 'ALTER SEQUENCE  "cadastralzone_Id_cz_seq"  RESTART WITH '|| idx;-- zašto ne idx-1 je obješnjeno u elaboratu, prije poglavlja baza
CLOSE c2;
end;
$$
language plpgsql;

CREATE or replace function my_normalizeIdCadastralZone() returns trigger as
$$
declare
c1 CURSOR FOR SELECT * FROM public.cadastralzone;-- zapisi nakon brisanja 
r1 public.cadastralzone%rowtype;
pom bigint = old."Id_cz"-1;
begin
OPEN c1;
FETCH LAST FROM c1 INTO r1;
IF not FOUND THEN ALTER SEQUENCE "cadastralzone_Id_cz_seq" RESTART WITH 1;
ELSIF r1."Id_cz"=pom THEN EXECUTE 'ALTER SEQUENCE "cadastralzone_Id_cz_seq" RESTART WITH '|| old."Id_cz"; -- zašto pom+1 a ne pom je isto objašnjeno u poglavlju elaborata -baza,
ELSE PERFORM my_sortiraj(OLD."Id_cz");
END IF;
CLOSE c1;
return old;
end;
$$
language plpgsql;

CREATE or replace TRIGGER bd_normalizeIdInCadastralZoneTrigger
AFTER DELETE ON cadastralzone 
-- KLJUCNO ZBOG OGRANICENJA PRIMATY KEY, DA SE NEDESI DA JOS UVJEK ZAPIS KOJI SE SMATRA IZBRISANIM SA OLD NALAZI U TABLI
FOR EACH ROW EXECUTE FUNCTION my_normalizeIdCadastralZone();
-- OVO ZA STATEMENT MENI JE POSEBNO ZANIMLJIVO, VOLIO BIH SKRENUTI PAZNJU NA ODBRANI 	NA ZNACENJE (konkretno optimizacija)



create or replace function my_sortirajParcele(i bigint) returns void as
$$
declare
c19 CURSOR (x bigint) FOR SELECT * FROM public.katastarskaparcela WHERE public.katastarskaparcela."extId_kp">x ;
r4 record;
idx bigint :=i;
begin
OPEN c19(idx);



FETCH FIRST FROM c19 INTO r4;

while FOUND  
			loop 
UPDATE public.katastarskaparcela SET "extId_kp"=idx WHERE CURRENT OF c19;
 idx:=idx+1;
 FETCH NEXT FROM c19 INTO r4;
			end loop;
			
EXECUTE 'ALTER SEQUENCE "katastarskaparcela_extId_kp_seq" RESTART WITH '|| idx;-- zašto ne idx-1 je obješnjeno u elaboratu, prije poglavlja baza
CLOSE c19;
end;
$$
language plpgsql;


CREATE or replace function my_normalizeIdCadastralParcel() returns trigger as
$$
declare
c20 CURSOR FOR SELECT * FROM public.katastarskaparcela;-- zapisi nakon brisanja 
r1 record;
pom bigint = old."extId_kp"-1;
begin
OPEN c20;
FETCH LAST FROM c20 INTO r1;
IF not FOUND THEN ALTER SEQUENCE public."katastarskaparcela_extId_kp_seq" RESTART WITH 1;
ELSIF r1."extId_kp"=pom THEN EXECUTE 'ALTER SEQUENCE "katastarskaparcela_extId_kp_seq" RESTART WITH '|| old."extId_kp"; -- zašto pom+1 a ne pom je isto objašnjeno u poglavlju elaborata -baza,
ELSE PERFORM my_sortirajParcele(OLD."extId_kp");
END IF;
CLOSE c20;
return old;
end;
$$
language plpgsql;

CREATE or replace TRIGGER ad_parcelIdTrigger
AFTER DELETE ON public.katastarskaparcela -- KLJUCNO ZBOG OGRANICENJA PRIMATY KEY,
--DA SE NEDESI DA JOS UVJEK ZAPIS KOJI SE SMATRA IZBRISANIM SA OLD NALAZI U TABLI
FOR EACH ROW EXECUTE FUNCTION my_normalizeIdCadastralParcel();
-- OVO ZA STATEMENT MENI JE POSEBNO ZANIMLJIVO, VOLIO BIH SKRENUTI PAZNJU NA ODBRANI 
--NA ZNACENJE (konkretno optimizacija)


