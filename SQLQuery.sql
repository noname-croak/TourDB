create view vAllTours as
select a.TourID, a.Departure, a.Returning, a.Price, b.[Name], b.[Type] as TourType, c.HotelName, d.CityName, d.[Population] as CityPopulation, d.Climate as CityClimate, e.CountryName, e.Capital as CountrysCapital, e.WorldPart from
Tours as a join [Routes] as b on a.RouteID = b.RouteID
join Hotels as c on b.HotelID = c.HotelID
join Cities as d on c.CityID = d.CityID
join Countries as e on d.CountryID = e.CountryID
go

create view vBoughtTours as
select a.TourID, a.Departure, a.Returning, a.Price, a.[Name], c.ClientID, (c.Name + ' ' + c.MiddleName + ' ' + c.LastName) as ClientName from
vAllTours as a join BoughtTours as b on a.TourID = b.TourID
join Clients as c on b.ClientID = c.ClientID
go

create view vBookedFlightTickets as
(select a.ClientID, a.ClientName, c.FlightID, (c.DepartureCity + '-' + c.ArrivalCity) as FlightName, c.Departure, c.Arrival, c.Price from
vBoughtTours as a join Tours_Flights as b on a.TourID = b.TourID
join Flights as c on b.FlightID = c.FlightID)
union
(select a.ClientID, a.ClientName, c.FlightID, (c.DepartureCity + '-' + c.ArrivalCity) as FlightName, c.Departure, c.Arrival, c.Price from
vBoughtTours as a join Tours_Flights as b on a.TourID = b.TourID
join Flights as c on b.BackFlightID = c.FlightID)
go

create view vBookedHotelRoom as
select a.ClientID, a.ClientName, d.HotelID, d.HotelName, d.PricePerDay, c.LengthDays, a.Departure as StartingDay, d.Phone as HotelPhone, d.Email as HotelEmail from
vBoughtTours as a join Tours as b on a.TourID = b.TourID
join [Routes] as c on b.RouteID = c.RouteID
join Hotels as d on c.HotelID = d.HotelID
go

create trigger tr_vBoughtTours
on vBoughtTours
instead of insert
as
begin
	if (((select ClientID from inserted) not in (select ClientID from Clients)) or ((select TourID from inserted) not in (select TourID from Tours)))
		begin
			rollback tran;
			throw 50001, 'Ввод некорректных значений, транзакция отменена', 0;
		end;
	declare @Client int
	declare @Tour int
	select @Client = ClientID from inserted
	select @Tour = TourID from inserted
	insert into BoughtTours (ClientID, TourID)
	values (@Client, @Tour)
end
go

create trigger tr_vBoughtToursDel
on vBoughtTours
instead of delete
as
begin
	declare @Client int
	declare @Tour int
	select @Client = ClientID from deleted
	select @Tour = TourID from deleted
	if not exists (select * from BoughtTours where ClientID = @Client and TourID = @Tour)
		begin
			rollback tran;
			throw 50001, 'Данный тур не был куплен данным пользователем', 0;
		end;
	delete from BoughtTours where ClientID = @Client and TourID = @Tour
end
go

create trigger tr_vBoughtToursChanged
on vBoughtTours
instead of update
as
begin
	if (UPDATE(TourID))
	begin
		declare @Client int
		select @Client = a.ClientID from deleted as a join inserted as b on a.ClientID = b.ClientID
		if (((select TourID from inserted) not in (select TourID from Tours)) or ((select TourID from deleted) not in (select TourID from Tours)) or not exists (select CLientID from Clients where ClientID = @Client))
		begin
			rollback tran;
			throw 50001, 'Ввод некорректных значений, транзакция отменена', 0;
		end;
		declare @OldTour int
		declare @NewTour int
		select @OldTour = TourID from deleted
		select @NewTour = TourID from inserted
		set rowcount 1
		update BoughtTours
		set TourID = @NewTour where ClientID = @Client and TourID = @OldTour
	end;
end
go

create procedure pr_BuyTour
	@ClientID int,
	@TourID int
	as
	begin
		if (((select Departure from Tours where TourID = @TourID) > GETDATE()) or not exists (select Departure from Tours where TourID = @TourID))
			insert into vBoughtTours (ClientID, TourID)
			values (@ClientID, @TourID)
		else
			print 'Данная путёвка уже распродана'
	end 
go

create procedure pr_ReturnTour
	@ClientID int,
	@TourID int
	as
	begin
		if (((select Departure from Tours where TourID = @TourID) > GETDATE()) or not exists (select Departure from Tours where TourID = @TourID))
			delete from vBoughtTours where ClientID = @ClientID and TourID = @TourID
		else
			print 'Путёвку можно сдать не позднее, чем за день до вылета'
	end
go

create procedure pr_ChangeTour
	@ClientID int,
	@TourID int,
	@NewTourID int
	as
	begin
		if (select Departure from Tours where TourID = @TourID) <= GETDATE()
			print 'Нельзя поменять просроченную путевку'
		else if (select Departure from Tours where TourID = @NewTourID) <= GETDATE()
			print 'Новая путевка уже распродана'
		else
		begin
			set rowcount 1
			update vBoughtTours
			set TourID = @NewTourID where ClientID = @ClientID and TourID = @TourID
		end;
	end
go

create procedure pr_AvailableTourByTypeAndMaxPrice
	@Type varchar(30),
	@MaxPrice money
	as
	begin
		declare @MinPrice money
		select @MinPrice = min(Price) from vAllTours
		if @Type not in (select distinct TourType from vAllTours)
			print 'Туры данного типа пока не устраиваются нашим агенством';
		else if (@MaxPrice < @MinPrice)
			print 'Туров по заданной цене пока нет';
		else
			select * from vAllTours where TourType = @Type and Price <= @MaxPrice and Departure > getdate()
	end
go

create procedure pr_ClientsHotel
	@ClientID int
	as
	begin
		if @ClientID not in (Select ClientID from Clients)
			print 'Неверный ID клиента';
		else if @ClientID not in (Select ClientID from BoughtTours)
			print 'Чтобы посмотреть забронированные отели, нужно сначала купить путёвку';
		else
			select * from vBookedHotelRoom where ClientID = @ClientID and StartingDay > GETDATE()
	end
go

create procedure pr_ClientsFlight
	@ClientID int
	as
	begin
		if @ClientID not in (Select ClientID from Clients)
			print 'Неверный ID клиента';
		else if @ClientID not in (Select ClientID from BoughtTours)
			print 'Чтобы посмотреть забронированные рейсы, нужно сначала купить путёвку';
		else
			select * from vBookedFlightTickets where ClientID = @ClientID and Departure > getdate()
	end
go

create function ufnRoutesPopularity ()
returns table
as
return
(
	select a.[Name], count(c.ClientID) as Ordered from [Routes] as a join Tours as b on a.RouteID = b.RouteID
	join BoughtTours as c on b.TourID = c.TourID group by a.[Name]
)
go

create function ufnClientsSpentMoney (@ClientID int)
returns money
begin
	declare @Money money
	if @ClientID not in (Select ClientID from BoughtTours)
		set @money = 0;
	else
		select @money = sum(Price) from vBoughtTours where ClientID = @ClientID
	return @money;
end
go

create function ufnAmountOfFlightsToCountries()
returns table
as
return
(
	select a.CountryName, count(d.FlightID) as FlightsAmount from Countries as a join Cities as b on a.CountryID = b.CountryID
	join Flights_Cities as c on b.CityID = c.ToCityID
	join Flights as d on c.FlightID = d.FlightID where a.CountryName != 'Russia'
	group by a.CountryName 
)
go	

--Пример
--Просмотр популярных маршрутов клиентом
select * from ufnRoutesPopularity() order by Ordered desc
--Поиск маршрута клиентом
execute pr_AvailableTourByTypeAndMaxPrice 'Sightseeing', 1300
--Покупка путёвки
execute pr_BuyTour 10, 16
--Клиент понял, что ошибся номеров тура
execute pr_ChangeTour 10, 16, 12
--Проверка заброниваролись ли места в отеле
execute pr_ClientsHotel 10
--Проверка забронировались ли белиты на рейсы
execute pr_ClientsFlight 10
--Просмотр затраченных денег в данном турагенстве
select dbo.ufnClientsSpentMoney(10)


--
select * from vAllTours
select * from vBoughtTours
select * from vBookedHotelRoom
select * from vBookedFlightTickets