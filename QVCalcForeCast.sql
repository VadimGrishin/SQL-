USE [BDMAP]
GO
/****** Object:  StoredProcedure [dbo].[QVcalcForecast]    Script Date: 04/15/2019 13:03:35 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dbo].[QVcalcForecast]
@ufpsid numeric(19),
@shift int = 0 -- сдвиг по месяца диапазона @d1, @d2. 1 - на месяц раньше
as

-- Рассчет прогноза заказов по рознице на основании QV
-- Добавить top MaxCntIfam по опсам
begin
--select * from qvdata

SET NOCOUNT on

--drop table #ifam, #po, #x, #t
declare	@id int,
		@ItemFamId numeric(19),
		@PostOfficeId numeric(19), 
		@qty int,
		@d1 datetime,
		@d2 datetime,
		@dd datetime


select	@dd = GETDATE()		
select	@d1 = Convert(datetime, '15-' + str(month(DATEADD(MONTH, -4 - @shift, @dd)),2) + '-' + str(YEAR(DATEADD(MONTH, -3, @dd)),4))
select	@d2 = dateadd(millisecond, -2, DATEADD(MONTH, 3, @d1))

select distinct ufpsid, postofficeid	into #po	from qvdata where supldate between @d1 and @d2 and ufpsid = @ufpsid and ready = 1
select distinct itemfamid				into #ifam	from QVdata where supldate between @d1 and @d2 and ufpsid = @ufpsid and ready = 1

/*
 select * from #ifam
 select * from #po
 select * from #ifam, #po
*/

create table #x (	id int, UfpsId numeric(19), PostOfficeId numeric(19), ItemFamId numeric(19), RetPrice real null, Prihod numeric(10,2) null, Realiz numeric(10,2) null, Rsum_ops real null, Nops int null, NopsAVG real null,
					Nmax int null, Ravg_ops real null, Ravg_ufps real null, CntOPS0 int null, CntOPS int null, Reff_ops real null, RubReff_ops real null, Reff_ufps real null, RubReff_Ufps real null, 
					SumReff_ops real null, SumRubReff_ops real null, Rsum_ufps_prihod numeric(10,2) null, Rsum_ufps_realiz numeric(10,2) null, SumReff_ufps real null, SumRubReff_ufps real null, 
					KFa real null, KFb real null, FromB bit default 0, KF real null, Ravg real null, R1 real null, qty int null)

insert	#x (id, UfpsId, PostOfficeId, ItemFamId)
(select	id = ROW_NUMBER() OVER (ORDER BY UfpsId, PostOfficeId, ItemFamId) ,
		UfpsId, PostOfficeId, ItemFamId
from	#po, #ifam
 )


delete	#x		-- 14.12.2018 з.40934
from	PostOffice
where	#x.PostOfficeId = PostOffice.Id
		and PostOffice.Lock = 1


update	#x
set		RetPrice = (select MAX(retprice) from QVdata where #x.UfpsId = QVdata.ufpsid and #x.ItemFamId = QVdata.ItemFamId)


-- select @d1, @d2

------------------------------------------------------------------------------------------------------------------------------
SELECT	UfpsId, PostOfficeId, ItemFamId, ItemId, SuplDate,
		Prihod =  1.000000 * SUM(prihod),
		Realiz = -1.000000 * SUM(realiz) 
into	#t
FROM	QVdata 
WHERE	QVdata.ufpsid = @ufpsid
		and supldate between @d1 and @d2 
		and ready = 1
group by UfpsId, PostOfficeId, ItemFamId, ItemId, SuplDate

Create Index i1 On #t(itemfamid, postofficeid)
Create Index i2 On #t(itemfamid, ufpsid)

update	#t
set		Realiz = Realiz * 1.2
where	Prihod <= Realiz


update	#x
set		Prihod = (	select SUM(Prihod) from	#t where #t.itemfamid = #x.itemfamid and #t.postofficeid = #x.postofficeid) ,
		Realiz = (	select SUM(Realiz) from	#t where #t.itemfamid = #x.itemfamid and #t.postofficeid = #x.postofficeid) 

/*
select * from #t where itemfamid = 23133 order by 1,2,3,4
select * from #x where itemfamid = 23133 order by 1,2,3,4

select * from #t
select * from #x
select * from #t order by 1,2,3,4

*/
------------------------------------------------------------------------------------------------------------------------------

update	#x
set		Rsum_ops =	isnull((	select	SUM(Realiz)				from #t where #t.itemfamid = #x.itemfamid and #t.postofficeid = #x.postofficeid), 0),
		Nops =		isnull((	select	COUNT(distinct itemid)	from #t where #t.itemfamid = #x.itemfamid and #t.postofficeid = #x.postofficeid), 0),


		Rsum_ufps_prihod = ISNULL((	select	SUM(Prihod)	from #t where #t.itemfamid = #x.itemfamid and #t.UfpsId = #x.UfpsId), 0),
		Rsum_ufps_realiz = ISNULL((	select	SUM(Realiz)	from #t where #t.itemfamid = #x.itemfamid and #t.UfpsId = #x.UfpsId), 0),

		
		Nmax =		isnull((	select	COUNT(distinct element.supldate)
								from	contr, contrapp, contrpos, element, item
								where	contr.id = contrapp.contrid
										and contrapp.id = contrpos.contrappid
										and contrpos.id = element.contrposid
										and element.itemid = item.id
										and contr.Retail = 1
										and item.itemfamid = #x.itemfamid
										and element.supldate between @d1 and @d2 ), 0),
		CntOPS0 =	isnull((	select	COUNT(distinct postofficeid)	from #t where #t.ufpsid = #x.UfpsId), 0),								
		CntOPS =	isnull((	select	COUNT(distinct postofficeid)	from #t where #t.itemfamid = #x.itemfamid and #t.ufpsid = #x.UfpsId), 0)


update	#x
set		Ravg_ops = case when Nops <> 0 then Rsum_ops / Nops else null end,
		NopsAVG =	(select AVG(1.0*Nops) from #x o where #x.UfpsId = o.UfpsId and #x.ItemFamId = o.ItemFamId and Nops <> 0)
					--isnull((	select	COUNT(distinct itemid)	from #t where #t.itemfamid = #x.itemfamid and #t.UfpsId = #x.UfpsId), 0) / CntOPS,

update	#x
set		Ravg_ufps = (select SUM(o.Ravg_ops) from #x o where #x.UfpsId = o.UfpsId and #x.ItemFamId = o.ItemFamId) / (case when #x.CntOPS <> 0 then #x.CntOPS else null end)

update	#x
set		Reff_ops = Ravg_ops*Nmax,
		Reff_ufps = Ravg_ufps*Nmax

update	#x
set		RubReff_ops =	Reff_ops	* RetPrice,
		RubReff_ufps =	Reff_ufps	* RetPrice

update	#x
set		SumReff_ops =		(	select SUM(Reff_ops)		from #x o where #x.PostOfficeId = o.PostOfficeId ),
		SumRubReff_ops =	(	select SUM(RubReff_ops)		from #x o where #x.PostOfficeId = o.PostOfficeId ),
		SumReff_ufps = 		(	select SUM(Reff_ufps)		from #x o where #x.UfpsId = o.UfpsId ) /CntOPS0,
		SumRubReff_ufps = 	(	select SUM(RubReff_ufps)	from #x o where #x.UfpsId = o.UfpsId ) /CntOPS0
		
update	#x		
set		KFa = case when (SumReff_ops <> 0 and SumRubReff_ops <> 0)		then 0.3 * Reff_ops		/ SumReff_ops	+ 0.7 * RubReff_ops		/ SumRubReff_ops		else 0 end,
		KFb = case when (SumReff_ufps <> 0 and SumRubReff_ufps <> 0 )	then 0.3 * Reff_ufps	/ SumReff_ufps	+ 0.7 * RubReff_ufps	/ SumRubReff_ufps		else 0 end

		
update	#x		
set		Ravg =	case	when	Prihod is not null or Realiz is not null		then Ravg_ops	else Ravg_ufps	end,
		KF =	case	when	Prihod is not null or Realiz is not null		then KFa		else KFb		end,
		FromB = case	when	Prihod is not null or Realiz is not null		then 0			else 1			end
		
		
update	#x		
set		R1 =	case	when FromB = 0 then Ravg/0.7/Nmax*Nops
						else Ravg/0.7/Nmax*NopsAVG
				end

update	#x		
set		qty =	case	when 0.4<R1 and R1<1 then 1 
						when 0.15<R1 and R1<=0.4 and FromB = 1 then 1 --0.05<R1 and 
						else ROUND(R1,0)
				end

/*
select *  from #x 
where	isnull(qty, 0) <> 0
order by 1

select * from #x order by 1
*/

-- drop table #y
select	[Зона] = #x.FromB + 1,
		[Индекс ОПС] = PostOffice.name,
		[Издание] = Itemfam.Short,
		[Цена] = #x.RetPrice,
		[Приход] =		 case when CntOPS = 0 then 0 else cast(case	when #x.FromB = 0 then  #x.Prihod else 1.0 * Rsum_ufps_prihod / CntOPS end as real) end,
		[Реализация] =	 case when CntOPS = 0 then 0 else cast(case	when #x.FromB = 0 then  #x.Realiz else 1.0 * Rsum_ufps_realiz / CntOPS end as real) end,
		[Номеров в ОПС] = case	when #x.FromB = 0 then  #x.Nops else NopsAVG end,
		[Номеров за период] = #x.Nmax,
		[KF] = #x.KF,
		[R1] = #x.R1,
		#x.qty,
		#x.PostOfficeId,
		#x.ItemFamId,
		PostOffice.MaxCntIfam
into	#y0		
from	#x, PostOffice, ItemFam
where	#x.PostOfficeId = PostOffice.Id
		and #x.ItemFamId = itemfam.id
order by 2, KF desc		


----------------------------------------------------------------------------------------------------------------------------
-- select * from #y
If object_id('tempdb..##y1') is not null Drop Table ##y1 
select	rn =	row_number() OVER(ORDER BY [Индекс ОПС], [KF] desc, [Издание] ),
		rn0 =	row_number() OVER(PARTITION BY [Индекс ОПС] ORDER BY [Индекс ОПС], [KF] desc, [Издание] ),
		* 
into	##y1
from	#y0

select * from ##y1
--order by 1, 2
----------------------------------------------------------------------------------------------------------------------------

/*
delete	#y1
where	rn0 > MaxCntIfam

select * from #y1
*/
end

