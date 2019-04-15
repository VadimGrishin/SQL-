USE [BDMAP]
GO
/****** Object:  StoredProcedure [dbo].[MSGNormRep2]    Script Date: 04/15/2019 12:39:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[MSGNormRep2] 
	@minweight float,
	@limit float,
	@beg datetime,
	@end  datetime
AS
-- Гришин В.А. 23.06.2016 
-- Эта процедура работает только на чтение и используется для расчета показателей номирования МСГ
-- Вызов из специального файла Excel
Begin
set nocount on
-- ВЫБОР item'ов ДЛЯ ПРОДУКТА
select 
		inv.Retail,
		itf.short,
		--ibd.itemid,
		isnull(it.MainId,ibd.itemid) itemid, 
		--it.nametail, 
		qty=sum(ibd.Qtyinc)+sum(ibd.QtyErr),
		big_tirag=
			case
				when sum(ibd.Qtyinc)+sum(ibd.QtyErr)>=@limit then 1
				else 0
			end,
		weightfact=min(ibd.weightfact),	
		flyer=	
			case
				when min(ibd.weightfact)<=@minweight then 1
				else 0
			end	
into #items4pr
from invoda inv, invbdoda ibd, item it, itemfam itf
where inv.dt_nak>=@beg-180 and inv.dt_nak<@end and
 inv.id=ibd.invodaid
and ibd.itemid= it.id
and it.itemfamid=itf.id
and invtypeid in(1,2,3,5,6,9,10,16,100) 
and not (itf.id in (706,59563)) -- 706 каталог МАП, 59563 - мини-каталог
group by inv.Retail,itf.short,isnull(it.MainId,ibd.itemid)--,it.nametail,itemid,
having max(inv.dt_nak)>=@beg and sum(ibd.Qtyinc)+sum(ibd.QtyErr)>0 --and max(inv.dt_nak)<@end
order by big_tirag,itf.short,itemid--qty --itf.short,it.nametail

--****************************************************
-- СОРТИРОВКА

-- вес позиции в Ф16
select st.f16id,  1/cast( COUNT(*)as float) f16ves --sbdCont.itemid,
into #f16
from sendtask st, SackBody sbd,SackBodyContent sbdCont 
where  st.datesend>=@beg and st.datesend<=@end and sbd.sendtaskid=st.id and sbdCont.sackbodyid=sbd.id 
group by st.f16id 

-- начало расчета бумаги по Ф16, все станции выгрузки и трактовки для расчета бумаги
select chanel.chtypeid ,f16.chanelid,chanel.name,st.f16id,st.id stid,st.number,st.sendpntId,sendpnt.name sndpname,st.TimeTableId, TimeTable.Name reis,
unloadname =	case	when	chtypeid = 1
				then	isnull((select	rtrim(t.name)
						from	trakt t
						where	t.id = trakt.unloadaviaid),
					'ПВ ' + dbo.padl(rtrim(trakt.vag),3,'0'))
				else	isnull((select	rtrim(t.name)
						from	trakt t
						where	t.id = trakt.unloadstatid),
					'ПВ ' + dbo.padl(rtrim(trakt.vag),3,'0'))
			end, --st.id stid,
			sdtraktid, trakt.name trname --, sbd.sacknum
into #f16for_paper
from sendtask st 
join f16 on f16.id=st.f16id
--join SackBody sbd on sbd.sendtaskid=st.id 
--join SackBodyContent sbdCont on sbdCont.sackbodyid=sbd.id
join chanel on chanel.id=f16.chanelid
join sendpnt on sendpnt.id=st.sendpntId
join TimeTable on st.TimeTableId=TimeTable.Id
join trakt on trakt.id = sendpnt.sdtraktid 
where  st.datesend>=@beg and st.datesend<=@end

-- Приложение к ФСП-36 
select #f16for_paper.chtypeid, f16id,  ceiling(cast (count(distinct TimeTableId)as float)/14)  PrilFSP36
into #PrilFSP36 
from #f16for_paper, F16RepChTypeLink lnk 
						where lnk.ChTypeId=#f16for_paper.chtypeid and
						lnk.F16ReportsId=5
group by #f16for_paper.chtypeid,f16id
--select * from #F16reestr order by f16id

-- Ф16 общая
select #f16for_paper.chtypeid, f16id,  ceiling(cast (count(distinct TimeTableId)as float)/14)  F16general
into #F16general 
from #f16for_paper, F16RepChTypeLink lnk 
						where lnk.ChTypeId=#f16for_paper.chtypeid and
						lnk.F16ReportsId=1
group by #f16for_paper.chtypeid,f16id

-- ФСП-36 
select #f16for_paper.chtypeid,f16id,TimeTableId,reis, 
ceiling(cast (COUNT(distinct unloadname)as float)/32) FSP36
into #FSP36_reis 
from #f16for_paper, F16RepChTypeLink lnk 
where lnk.ChTypeId=#f16for_paper.chtypeid and
						lnk.F16ReportsId=4
group by #f16for_paper.chtypeid,f16id,TimeTableId, reis 

select chtypeid,f16id,SUM(FSP36) FSP36 
into #FSP36 from #FSP36_reis
group by chtypeid,f16id

--ФСП-35
select #f16for_paper.chtypeid,f16id,TimeTableId,unloadname, 
ceiling(cast (COUNT(distinct sdtraktid)as float)/34) FSP35
into #FSP35_UL from #f16for_paper, F16RepChTypeLink lnk 
						where lnk.ChTypeId=#f16for_paper.chtypeid and
						lnk.F16ReportsId=3 
group by #f16for_paper.chtypeid,f16id,TimeTableId,unloadname 

select chtypeid,f16id,SUM(FSP35) FSP35 
into #FSP35 from #FSP35_UL
group by chtypeid,f16id

--Ф16А рейсовая
select #f16for_paper.chtypeid,f16id,TimeTableId,reis, 
	1+(case when COUNT(trname)-32<=0 then 0 else ceiling((cast (COUNT(trname) as float)-32)/40) end) F16Areis
into #F16Areis_reis
from #f16for_paper, F16RepChTypeLink lnk 
						where lnk.ChTypeId=#f16for_paper.chtypeid and
						lnk.F16ReportsId=2
group by #f16for_paper.chtypeid,f16id,TimeTableId,reis

select chtypeid,f16id,SUM(F16Areis) F16Areis 
into #F16Areis from #F16Areis_reis
group by chtypeid,f16id

--Ф16 реестр
select #f16for_paper.chtypeid,f16id, 1+case when COUNT(stid)-32<=0 then 0 
					else ceiling((cast (COUNT(stid) as  float)-32)/40) end F16reestr
into #F16reestr					
from #f16for_paper, F16RepChTypeLink lnk 
						where lnk.ChTypeId=#f16for_paper.chtypeid and
						lnk.F16ReportsId=7
group by #f16for_paper.chtypeid,f16id
--конец расчета бумаги по Ф16


-- выбор позиций весового контроля (мешок+item)
select wc.SackBodyId,wcc.ItemId,WeightControlId,wcc.Id,wcc.Qty,wc.[date]
into #wct
from dbo.WeightControl wc,dbo.WeightControlContent wcc--, #items4pr it
where wc.id=wcc.WeightControlId --and wcc.ItemId=it.ItemId
and wc.[date]>=@beg and wc.[date]<@end 

-- тип розницы по справочнику УФПС
select st.id stid, --st.number, 
rettype= (select top 1 retsorttypeid from retsorttypeufpslink rsu,sendpnt sp 
	where isnull(rsu.lastdate, getdate())>st.datesend and st.sendpntid=sp.id and rsu.orgid=sp.orgid) 
into #Rettype
from sendtask st 
where st.datesend>=@beg and st.datesend<=@end and st.retail=1 and not(st.number like '%В%') 

-- ОСНОВНОЙ КУБ по всем контактам за период
select st.retail,#items4pr.big_tirag, #items4pr.flyer,st.chanelid,st.f16id,st.id,st.TimeTableId,st.number,sbdCont.itemid sbdContitem,
	#Rettype.rettype,
	product=case
			when st.retail=1 then 'МАП роз'
			when st.Retail=0 and flyer=0 and big_tirag=0 then 'МАП под общ'
			when st.Retail=0 and flyer=0 and big_tirag=1 then 'МАП под кр тир'
			when st.Retail=0 and flyer=1  then 'МАП под лист'
	end,
	sort=case
		when number like '%/L%' then 'линия'
		else 'ручная'
	end, 
	pickup=case
		when exists(select chtypeid from chanel 
				where chanel.id=st.chanelid and (chanel.chtypeid in (6,10,15)) )  
				then 'self'
		else 'notself'
	end,
	типнакл = 
        CASE CHARINDEX('/', number)
         WHEN 0 THEN 'Нет'
         ELSE SUBSTRING(number, CHARINDEX('/', number), 10)
      END,
	#f16.f16ves,
	isnull(#PrilFSP36.PrilFSP36,0) PrilFSP36, 
	isnull(#F16general.F16general,0) F16general,
	isnull(#FSP36.FSP36,0) FSP36,
	isnull(#FSP35.FSP35,0) FSP35,
	isnull(#F16Areis.F16Areis,0) F16Areis,
	isnull(#F16reestr.F16reestr,0) F16reestr,
	--f16ves=1/cast((select COUNT(*) from sendtask st1, SackBody sbd1,SackBodyContent sbdCont1 
	--					where st1.f16id=st.f16id and sbd1.sendtaskid=st1.id and sbdCont1.sackbodyid=sbd1.id) as float),
	stves=1/cast((select COUNT(*) from SackBody sbd1,SackBodyContent sbdCont1 where sbd1.sendtaskid=st.id and sbdCont1.sackbodyid=sbd1.id) as float),
	sbdves=1/cast((select COUNT(*) from SackBodyContent sbdCont2 where sbdCont2.sackbodyid=sbd.id) as float),
	cntpos=1,
    item.weightfact,
    sleeve=(0.0025*sbdCont.qty*item.weightfact)/1000, -- вся формула для рукава (17.5+0.0025*sackbody.weightfact)/1000
	itweight=
		(case
			when #items4pr.itemid is null then 0
			else cast(sbdCont.qty*item.weightfact as float) /1000
		end),
	sbdid=sbd.id,
	sbdCont.qty,
	pickpk_totcnt=	case when item.packfact<>0 then
						case
							when floor (cast(sbdCont.Qty as float)/ item.packfact)>0 then 1.0
							else 0.0
						end
					else 0.0
					end,		
	pkinpick_totcnt=
					case when item.packfact<>0 then 
						floor (cast(sbdCont.Qty as float)/ item.packfact)
					else 0.0
					end,
	pickex_totcnt=
				case when item.packfact<>0 then
				  case
						  when (sbdCont.Qty)%item.packfact>0 then 1.0
						  else 0.0
				  end
				else 0.0
					end  ,
	exinpick_totcnt=
		case when item.packfact<>0 then(sbdCont.Qty)%item.packfact
		else 0.0
		end,
	pack4comis_totcnt=
					case when item.packfact<>0 then
						CAST(sbdCont.Qty as float)/item.packfact
					else 0.0
					end,
	wccqty=#wct.qty
	--wccqty=(select sum(wcc.qty) from WeightControl wc,WeightControlContent wcc
	--		where wc.id=wcc.WeightControlId and wcc.ItemId=sbdCont.itemid and wc.SackBodyId=sbd.Id)
into #sndtt		
from SackBodyContent sbdCont
join sackbody sbd on sbd.id=sbdCont.sackbodyid
join sendtask st on st.id=sbd.sendtaskid
join item  on item.id=sbdCont.itemid
join #items4pr on  #items4pr.retail=st.retail and #items4pr.itemid=isnull(item.mainid,item.id) 
left join #wct  on #wct.SackBodyId=sbd.Id and #wct.ItemId=sbdCont.itemid
--left join WeightControlContent wcc on wcc.ItemId=sbdCont.itemid
left join #f16 on st.f16id=#f16.f16id
left join #PrilFSP36 on st.f16id=#PrilFSP36.f16id 
left join #F16general on st.f16id=#F16general.f16id
left join #FSP36 on st.f16id=#FSP36.f16id
left join #FSP35 on st.f16id=#FSP35.f16id
left join #F16Areis on st.f16id=#F16Areis.f16id
left join #F16reestr on st.f16id=#F16reestr.f16id
left join #Rettype on #Rettype.stid=st.id
where  st.datesend>=@beg and st.datesend<=@end --wc.id=wcc.WeightControlId and

-- итог по отгрузкам
select isnull(rettype,0) rettype, product, sort, --,типнакл,pickup,id,number,
sum(f16ves) f16_totcnt, 
sum(wccqty) SortA_DevEx_TotCnt,
sum(stves) inv_totcnt, sum(sbdves) sack_totcnt,--max(sack_cnt)*AVG(kf) sack_totcnt,
SUM(pickpk_totcnt) pickpk_totcnt,SUM(pkinpick_totcnt) pkinpick_totcnt,
SUM(pickex_totcnt) pickex_totcnt,SUM(exinpick_totcnt) exinpick_totcnt,SUM(pack4comis_totcnt) pack4comis_totcnt,
SUM(0.001*weightfact*qty) out_wt,sum(sbdves)*0.0175+SUM(sleeve) sleeve_kg, -- вся формула для рукава (17.5+0.0025*sackbody.weightfact)/1000
sum((PrilFSP36+F16general+FSP36+FSP35+F16Areis+F16reestr)*f16ves) F16Paper, 
COUNT(distinct sbdContitem) itemcnt
--,sum(PrilFSP36*f16ves) PrilFSP36, 
--sum(F16general*f16ves) F16general,
--sum(FSP36*f16ves) FSP36,
--sum(FSP35*f16ves) FSP35,
--sum(F16Areis*f16ves) F16Areis,
--sum(F16reestr*f16ves) F16reestr
from #sndtt
where not(типнакл like '%В%')  
group by rettype,product, sort
order by  rettype,product, sort--sort,pickup,типнакл,id,number

END

