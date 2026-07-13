-- Create database
create database hotel;

-- Create schema 
create schema raw;

-- Use the created database and schema
use database hotel;
use schema raw;

-- ============================================================
-- FILE FORMAT & STAGE
-- ============================================================
-- Create CSV file format
create or replace file format hotel_file
    TYPE='CSV'
    FIELD_OPTIONALLY_ENCLOSED_BY='"'
    SKIP_HEADER=1
    NULL_IF=('NULL','null',' ');

-- Create stage to load CSV files
create or replace stage hotel_stage
file_format=hotel_file;

-- ============================================================
-- BRONZE LAYER (Raw Data)
-- ============================================================
-- Create raw table to store ingested data
create table hotel_bronze(
    booking_id string,
    hotel_id string,
    hotel_city string,
    customer_id string,
    customer_name string,
    customer_email string,
    check_in_date string,
    check_out_date string,
    room_type string,
    num_guests string,
    total_amount string,
    currency string,
    booking_status string   
);

-- Load CSV data into Bronze table
copy into hotel_bronze
from @hotel_stage
file_format=(format_name=hotel_file)
on_error='continue';

-- Preview raw data
select * from hotel_bronze limit 50;

-- ============================================================
-- SILVER LAYER (Data Cleaning & Standardization)
-- ============================================================
-- Create cleaned table with proper data types
create table silver_hotel(
    booking_id varchar,
    hotel_id varchar,
    hotel_city varchar,
    customer_id varchar,
    customer_name varchar,
    customer_email varchar,
    check_in_date date,
    check_out_date date,
    room_type varchar,
    num_guests integer,
    total_amount double,
    currency varchar,
    booking_status varchar
);

-- Check invalid email addresses
 select customer_email
 from hotel_bronze
 where not (customer_email like '%@%.%')
    or customer_email is null;

-- Check bookings with invalid dates
select check_in_date,check_out_date
from hotel_bronze
where try_to_date(check_out_date)<try_to_date(check_in_date);

-- Check negative booking amounts
select total_amount
from hotel_bronze
where try_to_number(total_amount)<0;

-- Review booking status values
select distinct booking_status
from hotel_bronze;

-- Clean and insert data into Silver layer
insert into silver_hotel
select
    booking_id,
    hotel_id,
    INITCAP(trim(hotel_city)) as hotel_city,
    customer_id,
    INITCAP(trim(customer_name)) as customer_name,
    case
        when customer_email like '%@%.%' then lower(trim(customer_email))
        else null
    end as customer_email,
    try_to_date(nullif(check_in_date,' ')) as check_in_date,
    try_to_date(nullif(check_out_date,' ')) as check_out_date,
    room_type,
    num_guests,
    abs(try_to_number(total_amount)) as total_amount,
    currency,
    case 
        when lower(booking_status) in ('confirmeeed','confirmd') then 'Confirmed'
        else booking_status
    end as booking_status
    from hotel_bronze
    where 
        try_to_date(check_in_date) is not null
        and try_to_date(check_out_date) is not null
        and try_to_date(check_out_date)>=try_to_date(check_in_date);

-- Preview cleaned data
select * from silver_hotel limit 30;

-- ============================================================
-- GOLD LAYER (Business Ready Tables)
-- ============================================================
-- Revenue and bookings by date
create table gold_monthly_revenue_bookings as 
select check_in_date as date,
    count(*) as total_booking,
    sum(total_amount) as total_revenue
from silver_hotel
group by check_in_date
order by date;

-- Revenue by hotel city
create table gold_revenue_city as 
select hotel_city,sum(total_amount) as total_revenue
from silver_hotel
group by hotel_city
order by total_revenue desc;

-- Preview Gold tables
select * from gold_monthly_revenue_bookings limit 30;
select * from gold_revenue_city limit 30;

-- Clean fact table for reporting
create table gold_clean as
select 
    booking_id,
    hotel_id,
    hotel_city,
    customer_id,
    customer_name,
    customer_email,
    check_in_date,
    check_out_date,
    room_type,
    num_guests,
    total_amount,
    currency,
    booking_status
from silver_hotel;

-- ============================================================
-- DASHBOARD TABLES FOR POWER BI
-- ============================================================
-- Revenue trend
create table date_revenue as
select date,total_revenue
from gold_monthly_revenue_bookings
order by date;

-- Booking trend
create table date_booking as
select date,total_booking
from gold_monthly_revenue_bookings
order by date;

-- Top 5 revenue generating cities
create table city_revenue as
select hotel_city,total_revenue
from gold_revenue_city
where total_revenue is not null
order by total_revenue desc
limit 5;

-- Bookings by room type
create table room_type as
select room_type,count(*) as total_bookings
from gold_clean
group by room_type
order by total_bookings desc;

-- Bookings by status
create table booking_status as
select booking_status,count(*) as total_bookings
from gold_clean
where booking_status is not null
group by booking_status;

-- ============================================================
-- KPI TABLES
-- ============================================================
-- Total Revenue KPI
create table total_revenue as
select sum(total_amount) as total_revenue
from gold_clean;

-- Total Bookings KPI
create table total_bookings as
select count(*) as total_bookings
from gold_clean;

-- Average Booking Value KPI
create table avg_booking_value as
select avg(total_amount) as svg_booking_value
from gold_clean;

-- Total Guests KPI
create table guests as
select sum(num_guests) as total_guests
from gold_clean;

